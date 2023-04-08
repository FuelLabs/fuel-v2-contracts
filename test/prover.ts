import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import { ethers } from 'hardhat';
import { BigNumber as BN, Contract } from 'ethers';
import { componentSign } from '../protocol/validators';
import { randomBytes } from 'crypto';
import { randomBytes32 } from '../protocol/utils';
import { ZERO } from '../protocol/constants';
import { MEMORY_SIZE, memoryRoot, generateMemoryContext } from '../protocol/prover/utils';

chai.use(solidity);
const { expect } = chai;

describe('MemoryUtils', async () => {
    let memoryUtils: Contract;
    before(async () => {
        const memoryUtilsFactory = await ethers.getContractFactory('MemoryUtils');
        memoryUtils = await memoryUtilsFactory.deploy();
        await memoryUtils.deployed();
    });

    it('test verifying a copy in memory', async () => {
        let repeats = 1;
        for (let r = 0; r < repeats; r++) {
            console.log('Creating Data Set...');
            let memory = generateTestMemory();

            let copyLength = 1024 * 64;
            let fromOffset = 2 ** MEMORY_SIZE - 1024 * 128 - 1024 * 32 * 7 + 512;
            let toOffset = 1024 * 128 + 1024 * 16 * 3 + 512;

            console.log('Generating Memory Context...');
            let [fromContext, _] = generateMemoryContext(memory, fromOffset, copyLength);
            console.log(fromContext);
            let [toContext, toContextProof] = generateMemoryContext(memory, toOffset, copyLength);
            console.log(toContext);
            console.log(toContextProof);

            console.log('Computing End State Memory Root...');
            let endMemory = memory.slice(0);
            for (let i = 0; i < copyLength; i++) endMemory[i + toOffset] = memory[i + fromOffset];
            console.log('End State Memory Root: ' + memoryRoot(endMemory));

            // 64KB - 2734894
            // 128KB - 5285752

            // using context proofs
            // 64KB - 1615622
            // 128KB - 2980338
            // 256KB - 5686979
            let root = '0x54453042ee94bf84543fa2a7d30cd75b63844de83fe4fd7f8e4e98c09e49382e';
            await memoryUtils.performCopy(
                root,
                memory.slice(fromOffset, fromOffset + copyLength),
                fromContext,
                toContext,
                toContextProof,
                { gasLimit: 30_000_000 }
            );
            console.log(await memoryUtils.merkleRoot());
            console.log('---------------------------------');
            expect(await memoryUtils.merkleRoot()).to.equal(
                '0xdedb618e3a6015fbe036f35131fa91133e6991a80f33dcad2acf030c84536e52'
            );
        }
    });

    it('test verifying a context proof', async () => {
        let repeats = 0;
        for (let r = 0; r < repeats; r++) {
            console.log('Creating Data Set...');
            let memory = generateTestMemory();

            let length = 1024 * 64;
            let offset = 2 ** MEMORY_SIZE - 1024 * 128 - 1024 * 32 * 7 + 512;

            console.log('Generating Memory Context...');
            let [context, proof] = generateMemoryContext(memory, offset, length);
            console.log(context);
            console.log(proof);

            // 64KB - 180224
            let root = '0x54453042ee94bf84543fa2a7d30cd75b63844de83fe4fd7f8e4e98c09e49382e';
            await memoryUtils.verifyMemoryContext(root, context, proof, { gasLimit: 30_000_000 });
            console.log(await memoryUtils.merkleRoot());
            console.log('---------------------------------');
            expect(await memoryUtils.merkleRoot()).to.equal(
                '0x54453042ee94bf84543fa2a7d30cd75b63844de83fe4fd7f8e4e98c09e49382e'
            );
        }
    });

    it('test merkling a subset of data with a given context', async () => {
        let repeats = 0;
        for (let r = 0; r < repeats; r++) {
            console.log('Creating Data Set...');
            let memory = generateTestMemory();

            //console.log('Computing Memory Root...');
            //console.log('Memory Root: ' + memoryRoot(memory));

            console.log('Generating Memory Context...');
            let length = 1024 * 64;
            let offset = 2 ** MEMORY_SIZE - 1024 * 128 - 1024 * 32 * 7 + 512;
            //let offset = 1024 * 7 + 512;
            let [context, _] = generateMemoryContext(memory, offset, length);
            console.log(context);

            // 1 - (64byte page) 90110
            // 1 - 100669
            // 64 - 100538
            // 1KB - 100538
            // 2KB - 139582
            // 4KB - 176696
            // 8KB - 251008
            // 16KB - 399649
            // 32KB - 698601
            // 64KB - 1291673
            // 128KB - 2482660
            await memoryUtils.memoryRoot(memory.slice(offset, offset + length), context, {
                gasLimit: 30_000_000,
            });
            console.log(await memoryUtils.merkleRoot());
            console.log('---------------------------------');
            expect(await memoryUtils.merkleRoot()).to.equal(
                '0x54453042ee94bf84543fa2a7d30cd75b63844de83fe4fd7f8e4e98c09e49382e'
            );
        }
    });
});

function generateMemoryContextFAST(memory: Uint8Array, offset: number, length: number) {
    return {
        offset: 66748544,
        startPad:
            '0xf1545d7e0807131a615d5ae3687647658a06f07cd08db993e5366f3f55e6c7e0b948217d5a653c467b266c9412f9c30c2fd349711464fab203a340186fd91437f2fd36e242aed0eaa0a554264eb54406f64f93ca1b36aed545378c77f5b334376f41d1adefe812c1f82f923d8fc295c708b0beda5781fa7addbf174ad47cd95f',
        endPad: '0x',
        startBuffer: [
            '0xbd230ae3b2a55218663006a1876ffa32354dbb076dad18e2c87d4b6f33be3672',
            '0xe4330f0e8639d6bd24c32c5e3899cf18e03f7b2c9ec0e49dc7da3ccd3989b2f3',
            '0xd0d3b873478d2192a717a5b4afaaeb248371dbd7476ee18f2f787b8c9c72e14a',
            '0x7ca0d50c2f943090cdf8b6c348ec45540a5e08225507cfdd7eacb3112ba41307',
            '0xdaf70816fcb86fdec07158e824365b20988cb946b113f53ebd2f79ed5c8c8059',
            '0x89d35f8f13e8d15609ffebee7abb78b222583ed6089f30b57c96cf2c83241029',
            '0xe9484bf8025134511fa95179f9d1d5744892bf6e1bc51a9d70ce417b0685db06',
            '0xfc39651191b178e52897d0b889a2c839452b50e95d5a722ae69dc1cad46e6b01',
            '0x4add8ef1083607ca26ba7af11293d8b7a35c5d4d03ddd767b96c98c6e14afe27',
        ],
        endBuffer: [],
    };
}

function generateMemoryContextFAST2(memory: Uint8Array, offset: number, length: number) {
    return {
        offset: 66748544,
        startPad:
            '0xf1545d7e0807131a615d5ae3687647658a06f07cd08db993e5366f3f55e6c7e0b948217d5a653c467b266c9412f9c30c2fd349711464fab203a340186fd91437f2fd36e242aed0eaa0a554264eb54406f64f93ca1b36aed545378c77f5b334376f41d1adefe812c1f82f923d8fc295c708b0beda5781fa7addbf174ad47cd95f',
        endPad: '0x',
        startBuffer: [
            '0xbd230ae3b2a55218663006a1876ffa32354dbb076dad18e2c87d4b6f33be3672',
            '0xe4330f0e8639d6bd24c32c5e3899cf18e03f7b2c9ec0e49dc7da3ccd3989b2f3',
            '0xd0d3b873478d2192a717a5b4afaaeb248371dbd7476ee18f2f787b8c9c72e14a',
            '0x7ca0d50c2f943090cdf8b6c348ec45540a5e08225507cfdd7eacb3112ba41307',
            '0xdaf70816fcb86fdec07158e824365b20988cb946b113f53ebd2f79ed5c8c8059',
            '0x89d35f8f13e8d15609ffebee7abb78b222583ed6089f30b57c96cf2c83241029',
            '0xe9484bf8025134511fa95179f9d1d5744892bf6e1bc51a9d70ce417b0685db06',
            '0xfc39651191b178e52897d0b889a2c839452b50e95d5a722ae69dc1cad46e6b01',
            '0x4add8ef1083607ca26ba7af11293d8b7a35c5d4d03ddd767b96c98c6e14afe27',
        ],
        endBuffer: [],
    };
}

function generateMemoryContextZERO(memory: Uint8Array, offset: number, length: number) {
    return {
        offset: 0,
        startPad: [],
        endPad: [],
        startBuffer: [],
        endBuffer: [],
    };
}

function generateTestMemory() {
    let seed = 18465164;
    let memory = new Uint8Array(2 ** 26);
    for (let i = 0; i < memory.length; i++) {
        seed = (seed * 7193) % 10247693;
        memory[i] = seed % 256;
    }
    return memory;
}
