import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import { ethers } from 'hardhat';
import { BigNumber as BN, Contract } from 'ethers';

export const MEMORY_BLOB_SIZE = 10;
export const MEMORY_SIZE = 26;

// Calculates the root of the given memory array
export function memoryRoot(memory: Uint8Array) {
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
    let bi = 0;

    // find bytes needed for padding
    const startDelta = offset % 2 ** MEMORY_BLOB_SIZE;
    const endDelta = (offset + length) % 2 ** MEMORY_BLOB_SIZE;
    const startIndex = offset - startDelta;
    const endIndex = endDelta == 0 ? offset + length : offset + length + (2 ** MEMORY_BLOB_SIZE - endDelta);
    const startPad = memory.slice(startIndex, offset);
    const endPad = memory.slice(offset + length, endIndex);

    // start the algorithm and stop when we get to the offset
    for (let i = 0; i < startIndex; ) {
        buffer[bi] = ethers.utils.sha256(memory.slice(i, i + 2 ** MEMORY_BLOB_SIZE));
        i = i + 2 ** MEMORY_BLOB_SIZE;

        let collapse = -1;
        for (let j = 0; j < 256; j++) {
            if ((i & (2 ** (j + 2 + MEMORY_BLOB_SIZE) - 1)) == 2 ** (j + 1 + MEMORY_BLOB_SIZE)) {
                collapse = j;
                break;
            }
        }
        bi = bi - collapse;
        for (let j = collapse; j >= 0; j--) {
            buffer[bi + (j - 1)] = ethers.utils.sha256(buffer[bi + (j - 1)] + buffer[bi + j].substring(2));
        }
    }

    // remember the current buffer as the starting buffer
    let startBuffer = buffer.slice(0, bi);

    // continue the algorithm to the end of the given length while recording minimum hash values for context proof
    let cpIndex = bi - 1;
    let cpHashes = [];
    let cpStartBytes = new Uint8Array(0);
    if (startIndex != offset) cpStartBytes = memory.slice(offset, startIndex + 2 ** MEMORY_BLOB_SIZE);
    let cpEndBytes = new Uint8Array(0);
    if (offset + length != endIndex) cpEndBytes = memory.slice(endIndex - 2 ** MEMORY_BLOB_SIZE, offset + length);
    for (let i = startIndex; i < endIndex; ) {
        let firstIteration = i == startIndex;
        buffer[bi] = ethers.utils.sha256(memory.slice(i, i + 2 ** MEMORY_BLOB_SIZE));
        i = i + 2 ** MEMORY_BLOB_SIZE;
        let lastIteration = !(i < endIndex);

        if (lastIteration && offset + length != endIndex) {
            cpHashes.push(...buffer.slice(cpIndex + 1, bi));
        }

        let collapse = -1;
        for (let j = 0; j < 256; j++) {
            if ((i & (2 ** (j + 2 + MEMORY_BLOB_SIZE) - 1)) == 2 ** (j + 1 + MEMORY_BLOB_SIZE)) {
                collapse = j;
                break;
            }
        }
        bi = bi - collapse;
        for (let j = collapse; j >= 0; j--) {
            buffer[bi + (j - 1)] = ethers.utils.sha256(buffer[bi + (j - 1)] + buffer[bi + j].substring(2));

            // ignore the first iteration if there is start padding in the context
            // also ignore the last iteration if there is end padding in the context
            if (!(firstIteration && startIndex != offset) && !(lastIteration && offset + length != endIndex)) {
                if (cpIndex == bi + j) {
                    cpIndex--;
                } else if (cpIndex == bi + (j - 1)) {
                    cpHashes.push(buffer[bi + j]);
                }
            }
        }
        if ((firstIteration && startIndex != offset) || (lastIteration && offset + length != endIndex)) {
            cpIndex = bi - 1;
        }
        if (lastIteration && offset + length == endIndex) {
            cpHashes.push(...buffer.slice(cpIndex + 1, bi));
        }
    }

    // finish running through the algorithm while recording what values get hashed for the end buffer
    let trackingEndIndex = bi - 1;
    let endBuffer = [];
    for (let i = endIndex; i < memory.length; ) {
        buffer[bi] = ethers.utils.sha256(memory.slice(i, i + 2 ** MEMORY_BLOB_SIZE));
        i = i + 2 ** MEMORY_BLOB_SIZE;

        let collapse = -1;
        for (let j = 0; j < 256; j++) {
            if ((i & (2 ** (j + 2 + MEMORY_BLOB_SIZE) - 1)) == 2 ** (j + 1 + MEMORY_BLOB_SIZE)) {
                collapse = j;
                break;
            }
        }
        bi = bi - collapse;
        for (let j = collapse; j >= 0; j--) {
            buffer[bi + (j - 1)] = ethers.utils.sha256(buffer[bi + (j - 1)] + buffer[bi + j].substring(2));
            if (trackingEndIndex == bi + j) {
                trackingEndIndex--;
            } else if (trackingEndIndex == bi + (j - 1)) {
                endBuffer.push(buffer[bi + j]);
            }
        }
    }

    // if the context proof start bytes and end bytes overlap then just put that overlap in start bytes
    if (endIndex - startIndex <= 2 ** MEMORY_BLOB_SIZE) {
        cpStartBytes = memory.slice(offset, offset + length);
        cpEndBytes = new Uint8Array(0);
    }

    // return context for merklizing memory subset in a larger tree
    let context = {
        offset,
        startPad: ethers.utils.hexlify(startPad),
        endPad: ethers.utils.hexlify(endPad),
        startBuffer,
        endBuffer,
    };
    let proof = {
        length,
        startBytes: ethers.utils.hexlify(cpStartBytes),
        endBytes: ethers.utils.hexlify(cpEndBytes),
        hashes: cpHashes,
    };
    return [context, proof];
}
