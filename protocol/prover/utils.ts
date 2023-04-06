import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import { ethers } from 'hardhat';
import { BigNumber as BN, Contract } from 'ethers';

export const MEMORY_BLOB_SIZE = 10;
export const MEMORY_SIZE = 26;

// Calculates the root of the given memory array
export function calculateMemoryRoot(memory: Uint8Array) {
    let buffer = [];
    for (let i = 0; i < 256; i++) buffer.push('');
    let bufferIndex = 0;

    for (let i = 0; i < memory.length; ) {
        buffer[bufferIndex] = ethers.utils.sha256(memory.slice(i, i + 2 ** MEMORY_BLOB_SIZE));
        i = i + 2 ** MEMORY_BLOB_SIZE;

        let collapse = -1;
        for (let j = 0; j < 256; j++) {
            if ((i & (2 ** (j + 2 + MEMORY_BLOB_SIZE) - 1)) == 2 ** (j + 1 + MEMORY_BLOB_SIZE)) {
                collapse = j;
                break;
            }
        }
        bufferIndex = bufferIndex - collapse;
        for (let j = collapse; j >= 0; j--) {
            buffer[bufferIndex + (j - 1)] = ethers.utils.sha256(
                buffer[bufferIndex + (j - 1)] + buffer[bufferIndex + j].substring(2)
            );
        }
    }
    return buffer[bufferIndex - 1];
}

// Generates a memory context object to prove existance of data subset at offset with given length
export function generateMemoryContext(memory: Uint8Array, offset: number, length: number) {
    let buffer = [];
    for (let i = 0; i < 256; i++) buffer.push('');
    let bufferIndex = 0;

    // find bytes needed for padding
    let startDelta = offset % 2 ** MEMORY_BLOB_SIZE;
    let endDelta = (offset + length) % 2 ** MEMORY_BLOB_SIZE;
    let startIndex = offset - startDelta;
    let endIndex = endDelta == 0 ? offset + length : offset + length + (2 ** MEMORY_BLOB_SIZE - endDelta);

    // start the algorithm and stop when we get to the offset
    for (let i = 0; i < startIndex; ) {
        buffer[bufferIndex] = ethers.utils.sha256(memory.slice(i, i + 2 ** MEMORY_BLOB_SIZE));
        i = i + 2 ** MEMORY_BLOB_SIZE;

        let collapse = -1;
        for (let j = 0; j < 256; j++) {
            if ((i & (2 ** (j + 2 + MEMORY_BLOB_SIZE) - 1)) == 2 ** (j + 1 + MEMORY_BLOB_SIZE)) {
                collapse = j;
                break;
            }
        }
        bufferIndex = bufferIndex - collapse;
        for (let j = collapse; j >= 0; j--) {
            buffer[bufferIndex + (j - 1)] = ethers.utils.sha256(
                buffer[bufferIndex + (j - 1)] + buffer[bufferIndex + j].substring(2)
            );
        }
    }

    // remember the current buffer as the starting buffer
    let startBuffer = buffer.slice(0, bufferIndex);

    // continue the algorithm to the end of the subset length
    for (let i = startIndex; i < endIndex; ) {
        buffer[bufferIndex] = ethers.utils.sha256(memory.slice(i, i + 2 ** MEMORY_BLOB_SIZE));
        i = i + 2 ** MEMORY_BLOB_SIZE;

        let collapse = -1;
        for (let j = 0; j < 256; j++) {
            if ((i & (2 ** (j + 2 + MEMORY_BLOB_SIZE) - 1)) == 2 ** (j + 1 + MEMORY_BLOB_SIZE)) {
                collapse = j;
                break;
            }
        }
        bufferIndex = bufferIndex - collapse;
        for (let j = collapse; j >= 0; j--) {
            buffer[bufferIndex + (j - 1)] = ethers.utils.sha256(
                buffer[bufferIndex + (j - 1)] + buffer[bufferIndex + j].substring(2)
            );
        }
    }

    // finish running through the algorithm while recording what values get hashed
    let trackingEndIndex = bufferIndex - 1;
    let endBuffer = [];
    for (let i = endIndex; i < memory.length; ) {
        buffer[bufferIndex] = ethers.utils.sha256(memory.slice(i, i + 2 ** MEMORY_BLOB_SIZE));
        i = i + 2 ** MEMORY_BLOB_SIZE;

        let collapse = -1;
        for (let j = 0; j < 256; j++) {
            if ((i & (2 ** (j + 2 + MEMORY_BLOB_SIZE) - 1)) == 2 ** (j + 1 + MEMORY_BLOB_SIZE)) {
                collapse = j;
                break;
            }
        }
        bufferIndex = bufferIndex - collapse;
        for (let j = collapse; j >= 0; j--) {
            buffer[bufferIndex + (j - 1)] = ethers.utils.sha256(
                buffer[bufferIndex + (j - 1)] + buffer[bufferIndex + j].substring(2)
            );
            if (trackingEndIndex == bufferIndex + j) {
                trackingEndIndex--;
            } else if (trackingEndIndex == bufferIndex + (j - 1)) {
                endBuffer.push(buffer[bufferIndex + j]);
            }
        }
    }

    // return context for merklizing memory subset in a larger tree
    return {
        offset,
        startPad: ethers.utils.hexlify(memory.slice(startIndex, offset)),
        endPad: ethers.utils.hexlify(memory.slice(offset + length, endIndex)),
        startBuffer,
        endBuffer,
    };
}
