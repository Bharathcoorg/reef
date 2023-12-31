import { Contract, utils } from 'ethers';
import erc20Abi from '../../assets/erc20Abi';
import ReefswapFactory from '../../assets/ReefswapFactoryAbi';
import config from '../../config';
import { RawEventData } from '../../crawler/types';
import { nodeProvider, queryv2 } from '../../utils/connector';
import logger from '../../utils/logger';
import TokenPrices from '../historyModules/TokenPrices';
import PoolEventBase from './PoolEventBase';
import { verifyPool } from './poolVerification';

class FactoryEvent extends PoolEventBase<RawEventData> {
  static verify = false;

  poolAddress?: string;

  tokenAddress1?: string;

  tokenAddress2?: string;

  decimal1?: number;

  decimal2?: number;

  async process(rawData: RawEventData): Promise<void> {
    await super.process(rawData);
    if (!FactoryEvent.isFactoryCreateEvent(rawData.address)) {
      throw new Error('Not a PairCreated ReefswapFactory event');
    }

    const contractInterface = new utils.Interface(ReefswapFactory);
    const data = contractInterface.parseLog(rawData);
    logger.info(`Reefswap Factory PairCreate event detected on evm even id: ${this.evmEventId}`);

    const [tokenAddress1, tokenAddress2, poolAddress] = data.args as string[];

    const tokenContract1 = new Contract(tokenAddress1, erc20Abi, nodeProvider.getProvider());
    const tokenContract2 = new Contract(tokenAddress2, erc20Abi, nodeProvider.getProvider());

    this.poolAddress = poolAddress;
    this.tokenAddress1 = tokenAddress1;
    this.tokenAddress2 = tokenAddress2;

    this.decimal1 = await tokenContract1.decimals();
    this.decimal2 = await tokenContract2.decimals();

    // Add new pool in TokenPrices
    TokenPrices.addPool(tokenAddress1, tokenAddress2);
  }

  async save(): Promise<void> {
    await super.save();
    if (!this.poolAddress || !this.tokenAddress1 || !this.tokenAddress2 || !this.decimal1 || !this.decimal2) {
      throw new Error('Not all required fields are set! Call process() first');
    }

    await queryv2(
      `INSERT INTO pool 
        (evm_event_id, address, token_1, token_2, decimal_1, decimal_2, pool_decimal)
      VALUES
        ($1, $2, $3, $4, $5, $6, $7);`,
      [
        this.evmEventId,
        this.poolAddress,
        this.tokenAddress1,
        this.tokenAddress2,
        this.decimal1,
        this.decimal2,
        18,
      ],
    );

    if (FactoryEvent.verify) {
      await verifyPool(this.poolAddress);
    }
  }

  static isFactoryCreateEvent(address: string): boolean {
    return address.toLowerCase() === config.reefswapFactoryAddress.toLowerCase();
  }
}

export default FactoryEvent;
