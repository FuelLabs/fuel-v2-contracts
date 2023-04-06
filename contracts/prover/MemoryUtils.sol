// SPDX-License-Identifier: UNLICENSED
// solhint-disable not-rely-on-time
pragma solidity 0.8.9;

contract MemoryUtils {
    uint256 public constant BLOB_SIZE = 10; //2**10 (1024bytes)
    uint256 public constant MEMORY_SIZE = 26; //2**26 (64MB)
    uint256 public constant MAX_DATA_SAMPLE = 2 ** 18; //256KB

    bytes32 public merkleRoot;

    struct MemoryCompressedSubset {
        bytes startPortion;
        bytes endPortion;
        bytes32[] blobHashes;
    }

    struct MemorySubsetContext {
        uint256 offset;
        bytes startPad;
        bytes endPad;
        bytes32[] startBuffer;
        bytes32[] endBuffer;
    }

    function performCopy(
        bytes32 root,
        bytes calldata data,
        MemorySubsetContext calldata dataContext,
        bytes calldata overwrittenData,
        MemorySubsetContext calldata overwrittenDataContext
    ) public returns (bytes32) {
        require(data.length == overwrittenData.length, "Data lengths must match");

        // calculate merkle root for data being copied
        bytes32 calcRoot = memoryMerkleRoot(data, dataContext);
        require(calcRoot == root, "Invalid data context");

        // calculate merkle root with data being over written
        bytes32 calcRootOverwritten = memoryMerkleRoot(overwrittenData, overwrittenDataContext);
        require(calcRootOverwritten == root, "Invalid overwritten data context");

        // calculate merkle root using new data
        merkleRoot = memoryMerkleRoot(data, overwrittenDataContext);
        return merkleRoot;
    }

    function memoryMerkleRoot(bytes calldata data, MemorySubsetContext calldata context) public returns (bytes32) {
        require(data.length > 0, "Data can't be empty");
        require(data.length <= MAX_DATA_SAMPLE, "Data too long");
        require(context.offset + data.length <= (2 ** MEMORY_SIZE), "Data out of bounds");
        require(context.startPad.length == (context.offset % (2 ** BLOB_SIZE)), "Incorrect context.startPad");
        require(
            0 == ((context.endPad.length + context.offset + data.length) % (2 ** BLOB_SIZE)),
            "Incorrect context.endPad"
        );
        unchecked {
            // start merkle algorithm at context
            bytes32[] memory buffer = new bytes32[]((MEMORY_SIZE - BLOB_SIZE) + 1);
            uint256 bufferIndex = context.startBuffer.length;
            for (uint256 i = 0; i < context.startBuffer.length; i++) {
                buffer[i] = context.startBuffer[i];
            }

            // compute first and last hash with extra context padding
            bytes32 firstHash = bytes32(0);
            bytes32 lastHash = bytes32(0);
            if (data.length < (2 ** BLOB_SIZE)) {
                firstHash = sha256(abi.encodePacked(context.startPad, data, context.endPad));
            } else {
                if (context.startPad.length > 0) {
                    firstHash = sha256(
                        abi.encodePacked(context.startPad, data[0:(2 ** BLOB_SIZE) - context.startPad.length])
                    );
                } else {
                    firstHash = sha256(data[0:(2 ** BLOB_SIZE)]);
                }
                if (context.endPad.length > 0) {
                    lastHash = sha256(
                        abi.encodePacked(
                            data[data.length - ((2 ** BLOB_SIZE) - context.endPad.length):data.length],
                            context.endPad
                        )
                    );
                } else {
                    lastHash = sha256(data[data.length - (2 ** BLOB_SIZE):data.length]);
                }
            }

            // continue the merkle algorithm
            uint256 startIndex = context.offset - context.startPad.length;
            uint256 endIndex = context.offset + data.length;
            for (uint256 i = startIndex; i < endIndex; ) {
                uint256 nextIndex = i + (2 ** BLOB_SIZE);
                if (i == startIndex) {
                    buffer[bufferIndex] = firstHash;
                } else if (nextIndex >= endIndex) {
                    buffer[bufferIndex] = lastHash;
                } else {
                    buffer[bufferIndex] = sha256(data[(i - context.offset):((i - context.offset) + (2 ** BLOB_SIZE))]);
                }
                i = nextIndex;

                // keep buffer collapsed
                if ((i & ((2 ** (1 + BLOB_SIZE)) - 1)) == (2 ** (0 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex + 1;
                } else if ((i & ((2 ** (2 + BLOB_SIZE)) - 1)) == (2 ** (1 + BLOB_SIZE))) {
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else if ((i & ((2 ** (3 + BLOB_SIZE)) - 1)) == (2 ** (2 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex - 1;
                    buffer[bufferIndex] = sha256(abi.encodePacked(buffer[bufferIndex], buffer[bufferIndex + 1]));
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else if ((i & ((2 ** (4 + BLOB_SIZE)) - 1)) == (2 ** (3 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex - 2;
                    buffer[bufferIndex + 1] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 1], buffer[bufferIndex + 2])
                    );
                    buffer[bufferIndex] = sha256(abi.encodePacked(buffer[bufferIndex], buffer[bufferIndex + 1]));
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else if ((i & ((2 ** (5 + BLOB_SIZE)) - 1)) == (2 ** (4 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex - 3;
                    buffer[bufferIndex + 2] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 2], buffer[bufferIndex + 3])
                    );
                    buffer[bufferIndex + 1] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 1], buffer[bufferIndex + 2])
                    );
                    buffer[bufferIndex] = sha256(abi.encodePacked(buffer[bufferIndex], buffer[bufferIndex + 1]));
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else if ((i & ((2 ** (6 + BLOB_SIZE)) - 1)) == (2 ** (5 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex - 4;
                    buffer[bufferIndex + 3] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 3], buffer[bufferIndex + 4])
                    );
                    buffer[bufferIndex + 2] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 2], buffer[bufferIndex + 3])
                    );
                    buffer[bufferIndex + 1] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 1], buffer[bufferIndex + 2])
                    );
                    buffer[bufferIndex] = sha256(abi.encodePacked(buffer[bufferIndex], buffer[bufferIndex + 1]));
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else if ((i & ((2 ** (7 + BLOB_SIZE)) - 1)) == (2 ** (6 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex - 5;
                    buffer[bufferIndex + 4] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 4], buffer[bufferIndex + 5])
                    );
                    buffer[bufferIndex + 3] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 3], buffer[bufferIndex + 4])
                    );
                    buffer[bufferIndex + 2] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 2], buffer[bufferIndex + 3])
                    );
                    buffer[bufferIndex + 1] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 1], buffer[bufferIndex + 2])
                    );
                    buffer[bufferIndex] = sha256(abi.encodePacked(buffer[bufferIndex], buffer[bufferIndex + 1]));
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else if ((i & ((2 ** (8 + BLOB_SIZE)) - 1)) == (2 ** (7 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex - 6;
                    buffer[bufferIndex + 5] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 5], buffer[bufferIndex + 6])
                    );
                    buffer[bufferIndex + 4] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 4], buffer[bufferIndex + 5])
                    );
                    buffer[bufferIndex + 3] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 3], buffer[bufferIndex + 4])
                    );
                    buffer[bufferIndex + 2] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 2], buffer[bufferIndex + 3])
                    );
                    buffer[bufferIndex + 1] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 1], buffer[bufferIndex + 2])
                    );
                    buffer[bufferIndex] = sha256(abi.encodePacked(buffer[bufferIndex], buffer[bufferIndex + 1]));
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else if ((i & ((2 ** (9 + BLOB_SIZE)) - 1)) == (2 ** (8 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex - 7;
                    buffer[bufferIndex + 6] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 6], buffer[bufferIndex + 7])
                    );
                    buffer[bufferIndex + 5] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 5], buffer[bufferIndex + 6])
                    );
                    buffer[bufferIndex + 4] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 4], buffer[bufferIndex + 5])
                    );
                    buffer[bufferIndex + 3] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 3], buffer[bufferIndex + 4])
                    );
                    buffer[bufferIndex + 2] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 2], buffer[bufferIndex + 3])
                    );
                    buffer[bufferIndex + 1] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 1], buffer[bufferIndex + 2])
                    );
                    buffer[bufferIndex] = sha256(abi.encodePacked(buffer[bufferIndex], buffer[bufferIndex + 1]));
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else if ((i & ((2 ** (10 + BLOB_SIZE)) - 1)) == (2 ** (9 + BLOB_SIZE))) {
                    bufferIndex = bufferIndex - 8;
                    buffer[bufferIndex + 7] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 7], buffer[bufferIndex + 8])
                    );
                    buffer[bufferIndex + 6] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 6], buffer[bufferIndex + 7])
                    );
                    buffer[bufferIndex + 5] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 5], buffer[bufferIndex + 6])
                    );
                    buffer[bufferIndex + 4] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 4], buffer[bufferIndex + 5])
                    );
                    buffer[bufferIndex + 3] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 3], buffer[bufferIndex + 4])
                    );
                    buffer[bufferIndex + 2] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 2], buffer[bufferIndex + 3])
                    );
                    buffer[bufferIndex + 1] = sha256(
                        abi.encodePacked(buffer[bufferIndex + 1], buffer[bufferIndex + 2])
                    );
                    buffer[bufferIndex] = sha256(abi.encodePacked(buffer[bufferIndex], buffer[bufferIndex + 1]));
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                } else {
                    // stop manually expanding code at this point since it's much less frequent
                    // ex. a blob size of 1KB would need to be merkling more than 1MB of data before this could hit more than once
                    for (uint256 j = 10; j < 256; j++) {
                        if ((i & ((2 ** ((j + 1) + BLOB_SIZE)) - 1)) == (2 ** (j + BLOB_SIZE))) {
                            bufferIndex = bufferIndex - (j - 1);
                            for (uint256 k = (j - 1); k > 0; k--) {
                                buffer[bufferIndex + (k - 1)] = sha256(
                                    abi.encodePacked(buffer[bufferIndex + (k - 1)], buffer[bufferIndex + k])
                                );
                            }
                            buffer[bufferIndex - 1] = sha256(
                                abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex])
                            );
                            break;
                        }
                    }
                }
            }

            // finish final hashing to get to merkle root
            uint256 endBufferIndex = 0;
            uint256 level = (bufferIndex + context.endBuffer.length) - 1;
            while (level > 0) {
                uint256 d = (2 ** MEMORY_SIZE) / (1 << level);
                if ((endIndex % (d << 1)) <= d) {
                    buffer[bufferIndex - 1] = sha256(
                        abi.encodePacked(buffer[bufferIndex - 1], context.endBuffer[endBufferIndex])
                    );
                    endBufferIndex = endBufferIndex + 1;
                } else {
                    bufferIndex = bufferIndex - 1;
                    buffer[bufferIndex - 1] = sha256(abi.encodePacked(buffer[bufferIndex - 1], buffer[bufferIndex]));
                }
                level = level - 1;
            }

            // done
            merkleRoot = buffer[0];
            return merkleRoot;
        }
    }
}
