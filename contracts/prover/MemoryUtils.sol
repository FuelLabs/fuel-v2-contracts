// SPDX-License-Identifier: UNLICENSED
// solhint-disable not-rely-on-time
pragma solidity 0.8.9;

contract MemoryUtils {
    uint256 public constant BLOB_SIZE = 10; //2**10 (1024bytes)
    uint256 public constant MEMORY_SIZE = 26; //2**26 (64MB)
    uint256 public constant MAX_DATA_SAMPLE = 2 ** 18; //256KB

    bytes32 public merkleRoot;

    struct MemoryContextProof {
        uint256 length;
        bytes startBytes;
        bytes endBytes;
        bytes32[] hashes;
    }

    struct MemoryContext {
        uint256 offset;
        bytes startPad;
        bytes endPad;
        bytes32[] startBuffer;
        bytes32[] endBuffer;
    }

    // Returns the new merkle root after copy a subset of data to a new location
    function performCopy(
        bytes32 root,
        bytes calldata data,
        MemoryContext calldata context,
        MemoryContext calldata destContext,
        MemoryContextProof calldata destContextProof
    ) public returns (bytes32) {
        // verify merkle root for data being copied
        bytes32 calcRoot = memoryRoot(data, context);
        require(calcRoot == root, "Invalid data context");

        // verify the destination context is correct
        require(data.length == destContextProof.length, "Invalid destination context length");
        require(verifyMemoryContext(root, destContext, destContextProof), "Invalid destination context");

        // calculate merkle root using new data
        merkleRoot = memoryRoot(data, destContext);
        return merkleRoot;
    }

    // Caluculates the merkle root given a subset of data and its context to the rest of the tree
    function memoryRoot(bytes calldata data, MemoryContext calldata context) public returns (bytes32) {
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
            uint256 bi = context.startBuffer.length;
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
                    buffer[bi] = firstHash;
                } else if (nextIndex >= endIndex) {
                    buffer[bi] = lastHash;
                } else {
                    buffer[bi] = sha256(data[(i - context.offset):((i - context.offset) + (2 ** BLOB_SIZE))]);
                }
                i = nextIndex;

                // keep buffer collapsed
                if ((i & ((2 ** (1 + BLOB_SIZE)) - 1)) == (2 ** (0 + BLOB_SIZE))) {
                    bi = bi + 1;
                } else if ((i & ((2 ** (2 + BLOB_SIZE)) - 1)) == (2 ** (1 + BLOB_SIZE))) {
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else if ((i & ((2 ** (3 + BLOB_SIZE)) - 1)) == (2 ** (2 + BLOB_SIZE))) {
                    bi = bi - 1;
                    buffer[bi] = sha256(abi.encodePacked(buffer[bi], buffer[bi + 1]));
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else if ((i & ((2 ** (4 + BLOB_SIZE)) - 1)) == (2 ** (3 + BLOB_SIZE))) {
                    bi = bi - 2;
                    buffer[bi + 1] = sha256(abi.encodePacked(buffer[bi + 1], buffer[bi + 2]));
                    buffer[bi] = sha256(abi.encodePacked(buffer[bi], buffer[bi + 1]));
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else if ((i & ((2 ** (5 + BLOB_SIZE)) - 1)) == (2 ** (4 + BLOB_SIZE))) {
                    bi = bi - 3;
                    buffer[bi + 2] = sha256(abi.encodePacked(buffer[bi + 2], buffer[bi + 3]));
                    buffer[bi + 1] = sha256(abi.encodePacked(buffer[bi + 1], buffer[bi + 2]));
                    buffer[bi] = sha256(abi.encodePacked(buffer[bi], buffer[bi + 1]));
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else if ((i & ((2 ** (6 + BLOB_SIZE)) - 1)) == (2 ** (5 + BLOB_SIZE))) {
                    bi = bi - 4;
                    buffer[bi + 3] = sha256(abi.encodePacked(buffer[bi + 3], buffer[bi + 4]));
                    buffer[bi + 2] = sha256(abi.encodePacked(buffer[bi + 2], buffer[bi + 3]));
                    buffer[bi + 1] = sha256(abi.encodePacked(buffer[bi + 1], buffer[bi + 2]));
                    buffer[bi] = sha256(abi.encodePacked(buffer[bi], buffer[bi + 1]));
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else if ((i & ((2 ** (7 + BLOB_SIZE)) - 1)) == (2 ** (6 + BLOB_SIZE))) {
                    bi = bi - 5;
                    buffer[bi + 4] = sha256(abi.encodePacked(buffer[bi + 4], buffer[bi + 5]));
                    buffer[bi + 3] = sha256(abi.encodePacked(buffer[bi + 3], buffer[bi + 4]));
                    buffer[bi + 2] = sha256(abi.encodePacked(buffer[bi + 2], buffer[bi + 3]));
                    buffer[bi + 1] = sha256(abi.encodePacked(buffer[bi + 1], buffer[bi + 2]));
                    buffer[bi] = sha256(abi.encodePacked(buffer[bi], buffer[bi + 1]));
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else if ((i & ((2 ** (8 + BLOB_SIZE)) - 1)) == (2 ** (7 + BLOB_SIZE))) {
                    bi = bi - 6;
                    buffer[bi + 5] = sha256(abi.encodePacked(buffer[bi + 5], buffer[bi + 6]));
                    buffer[bi + 4] = sha256(abi.encodePacked(buffer[bi + 4], buffer[bi + 5]));
                    buffer[bi + 3] = sha256(abi.encodePacked(buffer[bi + 3], buffer[bi + 4]));
                    buffer[bi + 2] = sha256(abi.encodePacked(buffer[bi + 2], buffer[bi + 3]));
                    buffer[bi + 1] = sha256(abi.encodePacked(buffer[bi + 1], buffer[bi + 2]));
                    buffer[bi] = sha256(abi.encodePacked(buffer[bi], buffer[bi + 1]));
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else if ((i & ((2 ** (9 + BLOB_SIZE)) - 1)) == (2 ** (8 + BLOB_SIZE))) {
                    bi = bi - 7;
                    buffer[bi + 6] = sha256(abi.encodePacked(buffer[bi + 6], buffer[bi + 7]));
                    buffer[bi + 5] = sha256(abi.encodePacked(buffer[bi + 5], buffer[bi + 6]));
                    buffer[bi + 4] = sha256(abi.encodePacked(buffer[bi + 4], buffer[bi + 5]));
                    buffer[bi + 3] = sha256(abi.encodePacked(buffer[bi + 3], buffer[bi + 4]));
                    buffer[bi + 2] = sha256(abi.encodePacked(buffer[bi + 2], buffer[bi + 3]));
                    buffer[bi + 1] = sha256(abi.encodePacked(buffer[bi + 1], buffer[bi + 2]));
                    buffer[bi] = sha256(abi.encodePacked(buffer[bi], buffer[bi + 1]));
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else if ((i & ((2 ** (10 + BLOB_SIZE)) - 1)) == (2 ** (9 + BLOB_SIZE))) {
                    bi = bi - 8;
                    buffer[bi + 7] = sha256(abi.encodePacked(buffer[bi + 7], buffer[bi + 8]));
                    buffer[bi + 6] = sha256(abi.encodePacked(buffer[bi + 6], buffer[bi + 7]));
                    buffer[bi + 5] = sha256(abi.encodePacked(buffer[bi + 5], buffer[bi + 6]));
                    buffer[bi + 4] = sha256(abi.encodePacked(buffer[bi + 4], buffer[bi + 5]));
                    buffer[bi + 3] = sha256(abi.encodePacked(buffer[bi + 3], buffer[bi + 4]));
                    buffer[bi + 2] = sha256(abi.encodePacked(buffer[bi + 2], buffer[bi + 3]));
                    buffer[bi + 1] = sha256(abi.encodePacked(buffer[bi + 1], buffer[bi + 2]));
                    buffer[bi] = sha256(abi.encodePacked(buffer[bi], buffer[bi + 1]));
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                } else {
                    // stop manually expanding code at this point since it's much less frequent
                    // ex. a blob size of 1KB would need to be merkling more than 1MB of data before this could hit more than once
                    for (uint256 j = 10; j < 256; j++) {
                        if ((i & ((2 ** ((j + 1) + BLOB_SIZE)) - 1)) == (2 ** (j + BLOB_SIZE))) {
                            bi = bi - (j - 1);
                            for (uint256 k = (j - 1); k > 0; k--) {
                                buffer[bi + (k - 1)] = sha256(abi.encodePacked(buffer[bi + (k - 1)], buffer[bi + k]));
                            }
                            buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                            break;
                        }
                    }
                }
            }

            // finish final hashing to get to merkle root
            uint256 endBufferIndex = 0;
            uint256 level = (bi + context.endBuffer.length) - 1;
            while (level > 0) {
                uint256 d = (2 ** MEMORY_SIZE) / (1 << level);
                if ((endIndex % (d << 1)) <= d) {
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], context.endBuffer[endBufferIndex]));
                    endBufferIndex = endBufferIndex + 1;
                } else {
                    bi = bi - 1;
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                }
                level = level - 1;
            }

            // done
            merkleRoot = buffer[0];
            return merkleRoot;
        }
    }

    // Caluculates the merkle root given a subset of data and its context to the rest of the tree
    function verifyMemoryContext(
        bytes32 root,
        MemoryContext calldata context,
        MemoryContextProof calldata proof
    ) public returns (bool) {
        require(proof.length > 0, "Invalid proof length");
        require(context.offset + proof.length <= (2 ** MEMORY_SIZE), "Data out of bounds");
        require(
            (context.startPad.length + proof.startBytes.length) % (2 ** BLOB_SIZE) == 0,
            "Incorrect proof.startBytes"
        );
        require((context.endPad.length + proof.endBytes.length) % (2 ** BLOB_SIZE) == 0, "Incorrect proof.endBytes");
        require(context.startPad.length == (context.offset % (2 ** BLOB_SIZE)), "Incorrect context.startPad");
        require(
            0 == ((context.endPad.length + context.offset + proof.length) % (2 ** BLOB_SIZE)),
            "Incorrect context.endPad"
        );
        unchecked {
            // start merkle algorithm at context
            bytes32[] memory buffer = new bytes32[]((MEMORY_SIZE - BLOB_SIZE) + 1);
            uint256 bi = context.startBuffer.length;
            for (uint256 i = 0; i < context.startBuffer.length; i++) {
                buffer[i] = context.startBuffer[i];
            }

            // calculate start and end indexes
            uint256 startIndex = context.offset - context.startPad.length;
            uint256 endIndex = context.offset + proof.length;
            if (context.endPad.length > 0) endIndex = endIndex + ((2 ** BLOB_SIZE) - context.endPad.length);

            // handle case where the data falls in a single blob
            if (endIndex - startIndex <= (2 ** BLOB_SIZE)) {
                buffer[bi] = sha256(abi.encodePacked(context.startPad, proof.startBytes, context.endPad));

                uint256 collapseVal = 0;
                for (; collapseVal < 256; collapseVal++) {
                    if ((endIndex & (2 ** (collapseVal + 1 + BLOB_SIZE) - 1)) == 2 ** (collapseVal + BLOB_SIZE)) {
                        break;
                    }
                }
                if (collapseVal == 0) {
                    bi = bi + 1;
                } else {
                    bi = bi - (collapseVal - 1);
                }
                for (uint256 j = collapseVal; j > 1; j--) {
                    buffer[bi + (j - 2)] = sha256(abi.encodePacked(buffer[bi + (j - 2)], buffer[bi + (j - 1)]));
                }
                if (collapseVal > 0) {
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                }
            } else {
                // perform first hash manually if start bytes are provided
                if (proof.startBytes.length > 0) {
                    buffer[bi] = sha256(abi.encodePacked(context.startPad, proof.startBytes));
                    startIndex = startIndex + (2 ** BLOB_SIZE);

                    uint256 collapseVal = 0;
                    for (; collapseVal < 256; collapseVal++) {
                        if ((startIndex & (2 ** (collapseVal + 1 + BLOB_SIZE) - 1)) == 2 ** (collapseVal + BLOB_SIZE)) {
                            break;
                        }
                    }
                    if (collapseVal == 0) {
                        bi = bi + 1;
                    } else {
                        bi = bi - (collapseVal - 1);
                    }
                    for (uint256 j = collapseVal; j > 1; j--) {
                        buffer[bi + (j - 2)] = sha256(abi.encodePacked(buffer[bi + (j - 2)], buffer[bi + (j - 1)]));
                    }
                    if (collapseVal > 0) {
                        buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                    }
                }
                if (proof.endBytes.length > 0) {
                    endIndex = endIndex - (2 ** BLOB_SIZE);
                }

                // use proof hashes to skip hashing data ourselves in as large of steps as possible
                uint256 skip = 0;
                uint256 collapse = 0;
                uint256 hashesIndex = 0;
                for (skip = 0; skip < 256; skip++) {
                    uint256 next = 2 ** (skip + 1 + BLOB_SIZE);
                    if ((startIndex & (next - 1)) == 2 ** (skip + BLOB_SIZE) || (startIndex + next) > endIndex) {
                        break;
                    }
                }
                for (uint256 i = startIndex; i < endIndex; ) {
                    buffer[bi] = proof.hashes[hashesIndex];
                    hashesIndex++;
                    i = i + 2 ** (skip + BLOB_SIZE);

                    // calculate the buffer collapse amount and the next skip as a bonus
                    uint256 previousSkip = skip;
                    for (skip = 0; skip < 256; skip++) {
                        uint256 next = 2 ** (skip + 1 + BLOB_SIZE);
                        if ((i & (next - 1)) == 2 ** (skip + BLOB_SIZE) || (i + next) > endIndex) {
                            break;
                        }
                    }
                    for (collapse = skip; collapse < 256; collapse++) {
                        if ((i & (2 ** (collapse + 1 + BLOB_SIZE) - 1)) == 2 ** (collapse + BLOB_SIZE)) {
                            break;
                        }
                    }
                    collapse = collapse - previousSkip;

                    // collapse the buffer
                    if (collapse == 0) {
                        bi = bi + 1;
                    } else {
                        bi = bi - (collapse - 1);
                    }
                    for (uint256 j = collapse; j > 1; j--) {
                        buffer[bi + (j - 2)] = sha256(abi.encodePacked(buffer[bi + (j - 2)], buffer[bi + (j - 1)]));
                    }
                    if (collapse > 0) {
                        buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                    }
                }

                // perform last hash manually if end bytes are provided
                if (proof.endBytes.length > 0) {
                    buffer[bi] = sha256(abi.encodePacked(proof.endBytes, context.endPad));
                    endIndex = endIndex + (2 ** BLOB_SIZE);

                    uint256 collapseVal = 0;
                    for (; collapseVal < 256; collapseVal++) {
                        if ((endIndex & (2 ** (collapseVal + 1 + BLOB_SIZE) - 1)) == 2 ** (collapseVal + BLOB_SIZE)) {
                            break;
                        }
                    }
                    if (collapseVal == 0) {
                        bi = bi + 1;
                    } else {
                        bi = bi - (collapseVal - 1);
                    }
                    for (uint256 j = collapseVal; j > 1; j--) {
                        buffer[bi + (j - 2)] = sha256(abi.encodePacked(buffer[bi + (j - 2)], buffer[bi + (j - 1)]));
                    }
                    if (collapseVal > 0) {
                        buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                    }
                }
            }

            // finish final hashing to get to merkle root
            uint256 endBufferIndex = 0;
            uint256 level = (bi + context.endBuffer.length) - 1;
            while (level > 0) {
                uint256 d = (2 ** MEMORY_SIZE) / (1 << level);
                if ((endIndex % (d << 1)) <= d) {
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], context.endBuffer[endBufferIndex]));
                    endBufferIndex = endBufferIndex + 1;
                } else {
                    bi = bi - 1;
                    buffer[bi - 1] = sha256(abi.encodePacked(buffer[bi - 1], buffer[bi]));
                }
                level = level - 1;
            }

            // done
            merkleRoot = buffer[0];
            return buffer[0] == root;
        }
    }
}
