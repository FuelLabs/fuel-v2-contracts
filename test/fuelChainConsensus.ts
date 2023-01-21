import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import { HarnessObject, setupFuel } from '../protocol/harness';
import BlockHeader, { computeBlockId } from '../protocol/blockHeader';
import { EMPTY } from '../protocol/constants';
import { compactSign } from '../protocol/validators';
import { computeAddress, parseEther, SigningKey } from 'ethers/lib/utils';
import { BigNumber, utils } from 'ethers';
import { randomBytes32 } from '../protocol/utils';
import hash from '../protocol/cryptography';
import { ethers } from 'hardhat';

chai.use(solidity);
const { expect } = chai;

//TODO: use the actual "BlockHeaderLite" instead of this mockup
class BlockHeaderLite {
    constructor(
        public prevRoot: string,
        public height: string,
        public timestamp: string,
        public applicationHash: string,
        public validatorsHash: string
    ) {}
}
class Validators {
    constructor(public addresses: string[], public stakes: string[], public requiredStake: string) {}
}
function computeHeaderHash(blockHeader: BlockHeaderLite): string {
    return hash(
        utils.solidityPack(
            ['bytes32', 'uint32', 'uint64', 'bytes32', 'bytes32'],
            [
                blockHeader.prevRoot,
                blockHeader.height,
                blockHeader.timestamp,
                blockHeader.applicationHash,
                blockHeader.validatorsHash,
            ]
        )
    );
}
function computeValidatorsHash(validators: Validators): string {
    return hash(
        utils.solidityPack(
            ['address[]', 'uint256[]', 'uint256'],
            [validators.addresses, validators.stakes, validators.requiredStake]
        )
    );
}

describe('Fuel Chain Consensus', async () => {
    let env: HarnessObject;

    // Contract constants
    const NUM_COMMIT_SLOTS = 240;
    const MAX_UNJUSTIFIEDED_COMMITS = 8;
    const EPOCH_VALIDATOR_SET_LAG = 2;
    const BLOCKS_PER_EPOCH = 10800;
    const TIME_PER_EPOCH = 10800;
    const TIME_TO_JUSTIFY = 10800;
    const TIME_TO_FINALIZE = 10800;

    // Test validators and blocks
    const NUM_VALIDATORS = 32;
    const epochEndBlocks: BlockHeaderLite[] = [];
    const validatorKeys: SigningKey[] = [];
    let validators: Validators;

    before(async () => {
        env = await setupFuel();

        // build validator set
        const validatorAddresses: string[] = [];
        const validatorStakes: string[] = [];
        for (let i = 0; i < NUM_VALIDATORS; i++) {
            const signer = new SigningKey(randomBytes32());
            validatorKeys.push(signer);
            validatorAddresses.push(computeAddress(signer.privateKey));
            validatorStakes.push('1');
        }
        validators = {
            addresses: validatorAddresses,
            stakes: validatorStakes,
            requiredStake: (Math.ceil((NUM_VALIDATORS * 2) / 3) + 1).toString(),
        };

        // build test blocks
        //TODO: update the actual block header to include validator info
        const timestamp = Math.floor(new Date().getTime() / 1000);
        const tai64Time = BigNumber.from(timestamp).add('4611686018427387914');
        for (let i = 0; i < Math.floor(NUM_COMMIT_SLOTS / 2); i++) {
            const header: BlockHeaderLite = {
                prevRoot: randomBytes32(),
                height: ((epochEndBlocks.length + 1) * BLOCKS_PER_EPOCH - 1).toString(),
                timestamp: tai64Time.add(epochEndBlocks.length * TIME_PER_EPOCH).toHexString(),
                applicationHash: randomBytes32(),
                validatorsHash: computeValidatorsHash(validators),
            };
            epochEndBlocks.push(header);
        }

        // move clock forward to a time when all blocks have finished
        ethers.provider.send('evm_increaseTime', [TIME_PER_EPOCH * epochEndBlocks.length]);
    });

    describe('Verify ownership', async () => {
        let signer0: string;
        let signer1: string;
        before(async () => {
            signer0 = env.addresses[0];
            signer1 = env.addresses[1];
        });

        it('Should be able to switch owner as owner', async () => {
            expect(await env.fuelChainConsensus.owner()).to.not.be.equal(signer1);

            // Transfer ownership
            await expect(env.fuelChainConsensus.transferOwnership(signer1)).to.not.be.reverted;
            expect(await env.fuelChainConsensus.owner()).to.be.equal(signer1);
        });

        it('Should not be able to switch owner as non-owner', async () => {
            expect(await env.fuelChainConsensus.owner()).to.be.equal(signer1);

            // Attempt transfer ownership
            await expect(env.fuelChainConsensus.transferOwnership(signer0)).to.be.revertedWith(
                'Ownable: caller is not the owner'
            );
            expect(await env.fuelChainConsensus.owner()).to.be.equal(signer1);
        });

        it('Should be able to switch owner back', async () => {
            expect(await env.fuelChainConsensus.owner()).to.not.be.equal(signer0);

            // Transfer ownership
            await expect(env.fuelChainConsensus.connect(env.signers[1]).transferOwnership(signer0)).to.not.be.reverted;
            expect(await env.fuelChainConsensus.owner()).to.be.equal(signer0);
        });
    });

    describe('Verify admin functions', async () => {
        before(async () => {});

        it('Should be able to set required bond as owner', async () => {
            //TODO
        });

        it('Should not be able to set required bond as non-owner', async () => {
            //TODO
        });

        it('Should be able to switch required bond back', async () => {
            //TODO
        });
    });

    describe('Verify commence open commits', async () => {
        before(async () => {});

        it('Should not be able to commence as non-owner', async () => {
            //TODO
        });

        it('Should not be able to commence without providing overrides for all possible bad blocks', async () => {
            //TODO: need more overrides
        });

        it('Should not be able to commence in a state that leaves future blocks unproveable', async () => {
            //TODO: next block can't be proven
        });

        it('Should be able to commence the commit process', async () => {
            const startingHashes: string[] = [];
            for (let i = 0; i < MAX_UNJUSTIFIEDED_COMMITS; i++) {
                if (i < EPOCH_VALIDATOR_SET_LAG) {
                    startingHashes.push(computeHeaderHash(epochEndBlocks[EPOCH_VALIDATOR_SET_LAG - (i + 1)]));
                } else {
                    startingHashes.push(randomBytes32());
                }
            }
            const startingBlock = epochEndBlocks[EPOCH_VALIDATOR_SET_LAG - 1];
            const startingBlockTimestamp = BigNumber.from(startingBlock.timestamp).sub('4611686018427387914');
            await expect(
                env.fuelChainConsensus.commence(startingHashes, EPOCH_VALIDATOR_SET_LAG - 1, startingBlockTimestamp)
            ).to.not.be.reverted;
        });
    });

    describe('Verify open commits', async () => {
        const bondOptions = { value: parseEther('1.0') };
        before(async () => {});

        it('Should be able to make commits', async () => {
            const startingBlockIndex = EPOCH_VALIDATOR_SET_LAG;
            for (let i = 0; i < MAX_UNJUSTIFIEDED_COMMITS; i++) {
                const commitBlock = epochEndBlocks[startingBlockIndex + i];
                const commitBlockTimestamp = BigNumber.from(commitBlock.timestamp).sub('4611686018427387914');
                await expect(
                    env.fuelChainConsensus.commit(computeHeaderHash(commitBlock), commitBlockTimestamp, bondOptions)
                ).to.not.be.reverted;
            }

            // wait for commits to finalize
            ethers.provider.send('evm_increaseTime', [TIME_TO_JUSTIFY + TIME_TO_FINALIZE]);
        });

        //TODO: make this its own section
        it('Should be able to unbond', async () => {
            await expect(env.fuelChainConsensus.unbond([EPOCH_VALIDATOR_SET_LAG])).to.not.be.reverted;

            const epochNums: number[] = [];
            for (let i = 1; i < MAX_UNJUSTIFIEDED_COMMITS; i++) epochNums.push(EPOCH_VALIDATOR_SET_LAG + i);
            await expect(env.fuelChainConsensus.unbond(epochNums)).to.not.be.reverted;
        });

        //TODO: make this its own section
        it('Should be able to prove commits', async () => {
            const blockIndex = EPOCH_VALIDATOR_SET_LAG + MAX_UNJUSTIFIEDED_COMMITS;
            const blockHeader = epochEndBlocks[blockIndex];
            const blockHash = computeHeaderHash(blockHeader);
            const blockTimestamp = BigNumber.from(blockHeader.timestamp).sub('4611686018427387914');
            await expect(
                env.fuelChainConsensus.commit(blockHash, blockTimestamp, bondOptions)
            ).to.not.be.reverted;

            // get signatures and prove block
            const validatorsBlockHeader = epochEndBlocks[blockIndex - 2];
            const signatures: string[] = [];
            const skipValidators: number[] = [];
            while(skipValidators.length < Math.floor(validatorKeys.length / 3)) {
                const skip = Math.floor(Math.random() * validatorKeys.length);
                if(skipValidators.indexOf(skip) == -1) skipValidators.push(skip);
            }
            for(let i=0; i<validatorKeys.length; i++) {
                if(skipValidators.indexOf(i) > 0) {
                    signatures.push('0x');
                } else {
                    signatures.push(await compactSign(validatorKeys[i], blockHash));
                }
            }
            await expect(env.fuelChainConsensus.prove(blockHeader, validatorsBlockHeader, validators, signatures)).to.not.be.reverted;
        });

        //TODO: add checks for all the fail cases
    });

    describe('Verify valid blocks', async () => {
        it('Should be able to verify valid block', async () => {
            const blockEpoch = 3;
            const blockHeight = epochEndBlocks[blockEpoch].height;
            const blockHash = computeHeaderHash(epochEndBlocks[blockEpoch]);
            expect(await env.fuelChainConsensus.finalized(blockHeight, blockHash)).to.be.equal(true);
        });

        it('Should not be able to verify invalid block', async () => {
            //TODO
        });
    });

    describe('Verify pause and unpause', async () => {
        it('Should not be able to pause as non-owner', async () => {
            expect(await env.fuelChainConsensus.paused()).to.be.equal(false);

            // Attempt pause
            await expect(env.fuelChainConsensus.connect(env.signers[1]).pause()).to.be.revertedWith(
                'Ownable: caller is not the owner'
            );
            expect(await env.fuelChainConsensus.paused()).to.be.equal(false);
        });

        it('Should be able to pause as owner', async () => {
            expect(await env.fuelChainConsensus.paused()).to.be.equal(false);

            // Pause
            await expect(env.fuelChainConsensus.pause()).to.not.be.reverted;
            expect(await env.fuelChainConsensus.paused()).to.be.equal(true);
        });

        it('Should not be able to unpause as non-owner', async () => {
            expect(await env.fuelChainConsensus.paused()).to.be.equal(true);

            // Attempt unpause
            await expect(env.fuelChainConsensus.connect(env.signers[1]).unpause()).to.be.revertedWith(
                'Ownable: caller is not the owner'
            );
            expect(await env.fuelChainConsensus.paused()).to.be.equal(true);
        });

        it('Should not be able to verify block messages when paused', async () => {
            const blockEpoch = 3;
            const blockHeight = epochEndBlocks[blockEpoch].height;
            const blockHash = computeHeaderHash(epochEndBlocks[blockEpoch]);
            await expect(env.fuelChainConsensus.finalized(blockHeight, blockHash)).to.be.revertedWith(
                'Pausable: paused'
            );
        });

        it('Should be able to unpause as owner', async () => {
            expect(await env.fuelChainConsensus.paused()).to.be.equal(true);

            // Unpause
            await expect(env.fuelChainConsensus.unpause()).to.not.be.reverted;
            expect(await env.fuelChainConsensus.paused()).to.be.equal(false);
        });

        it('Should be able to verify block when unpaused', async () => {
            const blockEpoch = 3;
            const blockHeight = epochEndBlocks[blockEpoch].height;
            const blockHash = computeHeaderHash(epochEndBlocks[blockEpoch]);
            expect(await env.fuelChainConsensus.finalized(blockHeight, blockHash)).to.be.equal(true);
        });
    });
});
