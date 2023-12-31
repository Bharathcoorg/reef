/* eslint-disable */
import logger from '../../utils/logger';
import Candlestick from './Candlestick';
import MarketHistoryModule from './MarketHistoryModule';
import Reserves from './Reserves';
import TokenPrices from './TokenPrices';
import Volume from './Volume';
/* eslint-enable */

const modules = [
  TokenPrices,
  Reserves,
  Volume,
  Candlestick,
];

class MarketHistory extends MarketHistoryModule {
  static async init(blockId: string): Promise<void> {
    logger.info(`Initializing market history for block ${blockId}`);

    for (const module of modules) {
      await module.init(blockId);
    }
  }

  static async save(blockId: string, timestamp: string): Promise<void> {
    for (const module of modules) {
      await module.save(blockId, timestamp);
    }
  }
}

export default MarketHistory;
