// SPDX-License-Identifier: UNLICENSED
// solhint-disable not-rely-on-time
pragma solidity 0.8.9;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {CryptographyLib} from "../lib/Cryptography.sol";

/// @notice Structure for epoch commits
struct Commit {
    bytes32 blockHash;
    address beneficiary;
    uint32 timestamp;
    bool honest;
    bool proven;
}

/// @notice Mock block header
// TODO: replace with actual header
struct BlockHeader {
    bytes32 prevRoot;
    uint32 height;
    uint64 timestamp;
    bytes32 applicationHash;
    bytes32 validatorsHash;
}
struct Validators {
    address[] addresses;
    uint256[] stakes;
    uint256 requiredStake;
}

// solhint-disable-next-line func-visibility
function serializeHeader(BlockHeader calldata header) pure returns (bytes memory) {
    return
        abi.encodePacked(
            header.prevRoot,
            (uint32)(header.height),
            header.timestamp,
            header.applicationHash,
            header.validatorsHash
        );
}

// solhint-disable-next-line func-visibility
function computeHeaderHash(BlockHeader calldata header) pure returns (bytes32) {
    return CryptographyLib.hash(serializeHeader(header));
}

// solhint-disable-next-line func-visibility
function serializeValidators(Validators calldata validators) pure returns (bytes memory) {
    return abi.encodePacked(validators.addresses, validators.stakes, validators.requiredStake);
}

// solhint-disable-next-line func-visibility
function computeValidatorsHash(Validators calldata validators) pure returns (bytes32) {
    return CryptographyLib.hash(serializeValidators(validators));
}

/// @notice The Fuel v2 Consensus contract.
contract FuelChainConsensus is Initializable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    ///////////////
    // Constants //
    ///////////////

    bytes32 public constant EMPTY_HASH = 0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855; //hash of nothing
    address public constant EMPTY_ADDRESS = address(0x00000000000000000000000000000000000000000000000000000000deadbeef);

    uint256 public constant NUM_COMMIT_SLOTS = 240; //30 days worth of commits
    uint256 public constant MAX_UNJUSTIFIEDED_COMMITS = 8;
    uint256 public constant EPOCH_VALIDATOR_SET_LAG = 2;
    uint256 public constant BLOCKS_PER_EPOCH = 10800;
    uint256 public constant TIME_PER_EPOCH = 10800;
    uint256 public constant TIME_TO_JUSTIFY = 10800;
    uint256 public constant TIME_TO_FINALIZE = 10800;

    ////////////
    // Events //
    ////////////

    event CommitSubmitted(uint256 indexed epochNum, bytes32 blockHash);
    //TODO: add event for proving

    /////////////
    // Storage //
    /////////////

    /// @dev The current PoA key
    Commit[NUM_COMMIT_SLOTS] private _commitSlots;

    /// @dev The number of the last committed epoch
    uint256 private _lastCommitEpoch;

    /// @dev The block timestamp of the last committed epoch
    uint256 private _lastCommittedBlockTimestamp;

    /// @dev The bond amount required to make commits
    uint256 private _requiredBond;

    //TODO: remove _authorityKey
    /// @dev The Current PoA key
    address private _authorityKey;

    /////////////////////////////
    // Constructor/Initializer //
    /////////////////////////////

    /// @notice Constructor disables initialization for the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Contract initializer to setup starting values
    /// @param key Public key of the block producer authority
    function initialize(address key) public initializer {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        //TODO: remove this "data filling"
        uint i = 0;
        for (i = 0; i < NUM_COMMIT_SLOTS; i++) {
            Commit storage commitSlot = _commitSlots[i];
            commitSlot.blockHash = EMPTY_HASH;
            commitSlot.beneficiary = EMPTY_ADDRESS;
            commitSlot.timestamp = uint32(2 ** 32 - 1);
            commitSlot.proven = false;
            commitSlot.honest = false;
        }

        // data
        //TODO: remove _authorityKey
        _authorityKey = key;
        _requiredBond = 1000000000000000000;
        _lastCommitEpoch = EPOCH_VALIDATOR_SET_LAG - 1;

        //start paused
        _pause();
    }

    /////////////////////
    // Admin Functions //
    /////////////////////

    //TODO: remove _authorityKey
    /// @notice Sets the PoA key
    /// @param key Address of the PoA authority
    function setAuthorityKey(address key) external onlyOwner {
        _authorityKey = key;
    }

    /// @notice Sets the required bond for commits
    /// @param bondAmount Bond amount required for making commits
    function setRequiredBond(uint256 bondAmount) external onlyOwner {
        _requiredBond = bondAmount;
    }

    /// @notice Pause block commitments
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause block commitments
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /// @notice Starts the open commit process
    /// @param overrideBlockHashes List of blocks to override since the last commit
    /// @param lastFinalizedEpoch The last epoch number considered finalized
    /// @param lastFinalizedBlockTimestamp The timestamp of the last epoch considered finalized
    function commence(
        bytes32[] calldata overrideBlockHashes,
        uint256 lastFinalizedEpoch,
        uint256 lastFinalizedBlockTimestamp
    ) external onlyOwner {
        uint256 i;

        //need to override all possibly unjustified/unfinalized epochs at time of halt
        uint256 minimumEpochOverrides = (TIME_TO_JUSTIFY + TIME_TO_FINALIZE) / TIME_PER_EPOCH;
        require(overrideBlockHashes.length >= minimumEpochOverrides, "need more overrides");

        //override previous commits
        for (i = 0; i < overrideBlockHashes.length; i++) {
            Commit storage commitSlot = _commitSlots[((_lastCommitEpoch + NUM_COMMIT_SLOTS) - i) % NUM_COMMIT_SLOTS];
            if (overrideBlockHashes[i] == bytes32(0)) {
                commitSlot.blockHash = EMPTY_HASH;
                commitSlot.beneficiary = EMPTY_ADDRESS;
                commitSlot.timestamp = uint32(2 ** 32 - 1);
            } else {
                commitSlot.blockHash = overrideBlockHashes[i];
                commitSlot.beneficiary = EMPTY_ADDRESS;
                commitSlot.timestamp = uint32(uint256(block.timestamp) - (TIME_TO_JUSTIFY + TIME_TO_FINALIZE));
                commitSlot.proven = false;
            }
        }
        //make sure next commit could be proven
        for (i = 0; i < EPOCH_VALIDATOR_SET_LAG; i++) {
            Commit storage commitSlot = _commitSlots[((lastFinalizedEpoch + NUM_COMMIT_SLOTS) - i) % NUM_COMMIT_SLOTS];
            require(
                uint256(block.timestamp) >= uint256(commitSlot.timestamp) + TIME_TO_JUSTIFY,
                "next block can't be proven"
            );
        }

        //update system data
        _lastCommitEpoch = lastFinalizedEpoch;
        _lastCommittedBlockTimestamp = lastFinalizedBlockTimestamp;

        //TODO: remember beneficiaries from overrides and transfer funds after all state changes have been made?

        //unhalt
        _unpause();
    }

    //////////////////////
    // Public Functions //
    //////////////////////

    //TODO: remove _authorityKey
    /// @notice Gets the currently set PoA key
    /// @return authority key
    function authorityKey() public view returns (address) {
        return _authorityKey;
    }

    /// @notice Gets the required bond to commit
    /// @return required bond
    function requiredBond() external view returns (uint256) {
        return _requiredBond;
    }

    /// @notice Gets the last comitted epoch
    /// @return last committed epoch
    function lastCommittedEpoch() external view returns (uint256) {
        return _lastCommitEpoch;
    }

    /// @notice Gets the last comitted epoch block timestamp
    /// @return last committed block timestamp
    function lastCommittedBlockTimestamp() external view returns (uint256) {
        return _lastCommittedBlockTimestamp;
    }

    //TODO: replace with "justified" and "finalized"
    /// @notice Verify a given block
    /// @param blockHash The hash of a block
    /// @param signature The signature over the block hash
    function verifyBlock(bytes32 blockHash, bytes calldata signature) external view whenNotPaused returns (bool) {
        return CryptographyLib.addressFromSignature(signature, blockHash) == _authorityKey;
    }

    /// @notice Checks if a given block is justified
    /// @param blockHeight The height of the block to check
    /// @param blockHash The hash of the block to check
    /// @return true if the block is justified
    function justified(uint256 blockHeight, bytes32 blockHash) external view whenNotPaused returns (bool) {
        uint256 epochNum = blockHeight / BLOCKS_PER_EPOCH;
        if (epochNum > _lastCommitEpoch) return false;
        Commit storage commitSlot = _commitSlots[epochNum % NUM_COMMIT_SLOTS];
        require(commitSlot.blockHash == blockHash, "block not in commit memory");

        return uint256(block.timestamp) >= uint256(commitSlot.timestamp) + TIME_TO_JUSTIFY;
    }

    /// @notice Checks if a given block is finalized
    /// @param blockHeight The height of the block to check
    /// @param blockHash The hash of the block to check
    /// @return true if the block is finalized
    function finalized(uint256 blockHeight, bytes32 blockHash) external view whenNotPaused returns (bool) {
        uint256 epochNum = blockHeight / BLOCKS_PER_EPOCH;
        if (epochNum > _lastCommitEpoch) return false;
        Commit storage commitSlot = _commitSlots[epochNum % NUM_COMMIT_SLOTS];
        require(commitSlot.blockHash == blockHash, "block not in commit memory");

        return uint256(block.timestamp) >= uint256(commitSlot.timestamp) + TIME_TO_JUSTIFY + TIME_TO_FINALIZE;
    }

    /// @notice Optimistically commit the end of an epoch
    /// @param blockHash The hash of the last block in the epoch
    /// @param blockTimestamp The timestamp of the last block in the epoch
    function commit(bytes32 blockHash, uint256 blockTimestamp) external payable whenNotPaused {
        //verify bond
        require(msg.value == _requiredBond, "incorrect bond");

        //verify epoch
        require(blockTimestamp >= _lastCommittedBlockTimestamp + TIME_PER_EPOCH, "bad timestamp");
        require(uint256(block.timestamp) >= _lastCommittedBlockTimestamp + TIME_PER_EPOCH, "too soon");

        //verify provable
        uint256 epochNum = _lastCommitEpoch + 1;
        uint256 finalizedSlot = ((epochNum + NUM_COMMIT_SLOTS) - MAX_UNJUSTIFIEDED_COMMITS) % NUM_COMMIT_SLOTS;
        require(
            uint256(block.timestamp) >= uint256(_commitSlots[finalizedSlot].timestamp) + TIME_TO_JUSTIFY,
            "too far ahead"
        );

        //set epoch data at slot
        uint256 slot = epochNum % NUM_COMMIT_SLOTS;
        Commit storage commitSlot = _commitSlots[slot];
        commitSlot.blockHash = blockHash;
        commitSlot.beneficiary = msg.sender;
        commitSlot.timestamp = uint32(block.timestamp);
        commitSlot.proven = false;
        commitSlot.honest = true;

        //update commit epoch number
        _lastCommitEpoch = epochNum;
        _lastCommittedBlockTimestamp = blockTimestamp;

        emit CommitSubmitted(epochNum, blockHash);
    }

    /// @notice Prove a commit correct or otherwise 
    /// @param blockHeader The header of the last block in the committed epoch
    /// @param validatorsBlockHeader The header of the last block in the validator establishing epoch
    /// @param validators The validator info in the validator establishing block
    /// @param signatures The validator signatures for the last block in the committed epoch
    function prove(
        BlockHeader calldata blockHeader,
        BlockHeader calldata validatorsBlockHeader,
        Validators calldata validators,
        bytes[] calldata signatures
    ) external whenNotPaused {
        //verify the block headers are at the end of epochs and are the correct distance apart
        require((blockHeader.height + 1) % BLOCKS_PER_EPOCH == 0, "block not end of epoch");
        require((validatorsBlockHeader.height + 1) % BLOCKS_PER_EPOCH == 0, "validator block not end of epoch");
        uint256 epochNum = blockHeader.height / BLOCKS_PER_EPOCH;
        uint256 validatorEpochNum = validatorsBlockHeader.height / BLOCKS_PER_EPOCH;
        require(epochNum == validatorEpochNum + EPOCH_VALIDATOR_SET_LAG, "invalid block header heights");

        //get commit data for both blocks
        Commit storage commitSlot = _commitSlots[epochNum % NUM_COMMIT_SLOTS];
        Commit storage validatorCommitSlot = _commitSlots[validatorEpochNum % NUM_COMMIT_SLOTS];

        //determine if the provided block header is different than what was comitted
        bytes32 blockHeaderHash = computeHeaderHash(blockHeader);
        uint32 adjustedBlockTimestamp = uint32((uint256(blockHeader.timestamp) - 4611686018427387914));
        bool isBlockHeaderDifferent = blockHeaderHash != commitSlot.blockHash ||
            (epochNum == _lastCommitEpoch && adjustedBlockTimestamp != _lastCommittedBlockTimestamp);

        //verify the validator block header matches and is finalized
        require(validatorsBlockHeader.validatorsHash == computeValidatorsHash(validators), "invalid validators");
        require(validatorCommitSlot.blockHash == computeHeaderHash(validatorsBlockHeader), "invalid validator block");
        require(
            uint256(block.timestamp) >= uint256(validatorCommitSlot.timestamp) + TIME_TO_JUSTIFY,
            "validator block not justified"
        );

        //verify the proving block header is not finalized and not already proven
        require(
            uint256(block.timestamp) < uint256(commitSlot.timestamp) + TIME_TO_JUSTIFY + TIME_TO_FINALIZE,
            "block already finalized"
        );
        require(!commitSlot.proven || isBlockHeaderDifferent, "block already proven");

        //verify signatures
        uint256 totalStake = 0;
        for (uint256 i = 0; i < validators.addresses.length && totalStake < validators.requiredStake; i += 1) {
            //can include '0x' for missing signatures to skip ecrecover and minimize gas costs
            if (
                signatures[i].length > 0 &&
                CryptographyLib.addressFromSignature(signatures[i], blockHeaderHash) == validators.addresses[i]
            ) {
                totalStake += validators.stakes[i];
            }
        }
        require(totalStake >= validators.requiredStake, "block not validated");

        //check if proven different, the same, or should we halt
        if (!commitSlot.proven) {
            if (isBlockHeaderDifferent) {
                //update commit with what was proven
                commitSlot.blockHash = blockHeaderHash;
                commitSlot.beneficiary = msg.sender;
                commitSlot.honest = false;

                //adjust lastCommittedBlockTimestamp if this is lastCommitEpoch
                if (epochNum == _lastCommitEpoch) _lastCommittedBlockTimestamp = adjustedBlockTimestamp;
            }
            commitSlot.proven = true;

            //adjust timestamp for earlier justification if not already justified
            if (commitSlot.timestamp + TIME_TO_JUSTIFY > uint256(block.timestamp)) {
                commitSlot.timestamp = uint32(uint256(block.timestamp) - TIME_TO_JUSTIFY);
            }
        } else {
            //HALT!!! the block has already been proven once with a different block hash
            commitSlot.beneficiary = EMPTY_ADDRESS;
            _pause();
        }
    }

    /// @notice Reclaim bonds from finalized commits
    /// @param epochNums List of epoch numbers to reclaim bonds
    function unbond(uint256[] calldata epochNums) external whenNotPaused {
        uint i = 0;
        for (i = 0; i < epochNums.length; i++) {
            uint256 slot = epochNums[i] % NUM_COMMIT_SLOTS;
            Commit storage commitSlot = _commitSlots[slot];
            require(
                uint256(block.timestamp) >= uint256(commitSlot.timestamp) + TIME_TO_JUSTIFY + TIME_TO_FINALIZE,
                "not finalized"
            );

            address payable beneficiary = payable(commitSlot.beneficiary);
            require(commitSlot.beneficiary != EMPTY_ADDRESS, "already unbonded");

            commitSlot.beneficiary = EMPTY_ADDRESS;
            beneficiary.transfer(_requiredBond);
        }
    }

    ////////////////////////
    // Internal Functions //
    ////////////////////////

    /// @notice Executes a message in the given header
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        //should revert if msg.sender is not authorized to upgrade the contract (currently only owner)
    }
}
