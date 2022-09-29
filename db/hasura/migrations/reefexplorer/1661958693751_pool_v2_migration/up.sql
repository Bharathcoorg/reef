-- Dropping old views-- Dropping pool views
DROP VIEW IF EXISTS pool_day_fee;
DROP VIEW IF EXISTS pool_hour_fee;
DROP VIEW IF EXISTS pool_minute_fee;

DROP VIEW IF EXISTS pool_day_supply;
DROP VIEW IF EXISTS pool_hour_supply;
DROP VIEW IF EXISTS pool_minute_supply;

DROP VIEW IF EXISTS pool_day_volume;
DROP VIEW IF EXISTS pool_hour_volume;
DROP VIEW IF EXISTS pool_minute_volume;

DROP VIEW IF EXISTS pool_day_candlestick;
DROP VIEW IF EXISTS pool_hour_candlestick;
DROP VIEW IF EXISTS pool_minute_candlestick;

-- Dropping pool functions
DROP FUNCTION IF EXISTS pool_fee;
DROP FUNCTION IF EXISTS pool_supply;
DROP FUNCTION IF EXISTS pool_volume;
DROP FUNCTION IF EXISTS pool_candlestick;

DROP FUNCTION IF EXISTS pool_ratio;
DROP FUNCTION IF EXISTS pool_prepare_fee_data;
DROP FUNCTION IF EXISTS pool_prepare_volume_data;
DROP FUNCTION IF EXISTS pool_prepare_supply_data;

-- Restarting pool sequence
ALTER SEQUENCE pool_event_sequence RESTART WITH 1;

-- Dropping pool columns: pool_decimal, decimal_1, decimal_2
ALTER TABLE pool DROP COLUMN IF EXISTS pool_decimal CASCADE;

-- New tables
CREATE TABLE IF NOT EXISTS token_price(
  id SERIAL PRIMARY KEY,
  block_id INT NOT NULL,
  token_address CHAR(42) NOT NULL,
  price numeric NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL,
  
  FOREIGN KEY (block_id) REFERENCES block(id) ON DELETE CASCADE,
  CONSTRAINT token_price_unique UNIQUE (block_id, token_address)
);

CREATE INDEX IF NOT EXISTS token_price_block_id_idx ON token_price(block_id);
CREATE INDEX IF NOT EXISTS token_price_token_address_idx ON token_price(token_address);
CREATE INDEX IF NOT EXISTS token_price_timestamp_idx ON token_price(timestamp);

CREATE TABLE IF NOT EXISTS candlestick(
  id Serial PRIMARY KEY,
  
  block_id INT NOT NULL,
  pool_id INT NOT NULL,
  token_address CHAR(42) NOT NULL,
  
  open NUMERIC NOT NULL,
  high NUMERIC NOT NULL,
  low NUMERIC NOT NULL,
  close NUMERIC NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL,
  
  FOREIGN key (pool_id) REFERENCES pool(id) ON DELETE CASCADE,
  FOREIGN key (block_id) REFERENCES block(id) ON DELETE CASCADE,
  FOREIGN key (evm_event_id) REFERENCES evm_event(id) ON DELETE CASCADE,

  CONSTRAINT pool_block_token_candlestick UNIQUE (block_id, pool_id, token_address)
);

CREATE INDEX IF NOT EXISTS candlestick_block_id_idx ON candlestick(block_id);
CREATE INDEX IF NOT EXISTS candlestick_pool_id_idx ON candlestick(pool_id);
CREATE INDEX IF NOT EXISTS candlestick_token_address_idx ON candlestick(token_address);
CREATE INDEX IF NOT EXISTS candlestick_timestamp_idx ON candlestick(timestamp);
CREATE INDEX IF NOT EXISTS candlestick_evm_event_id_idx ON candlestick(evm_event_id);

CREATE TABLE IF NOT EXISTS reserved_raw(
  id Serial PRIMARY KEY,
  
  block_id INT NOT NULL,
  pool_id INT NOT NULL,
  evm_event_id INT, -- Optional link to evm event
  
  reserved_1 NUMERIC NOT NULL,
  reserved_2 NUMERIC NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL,
  
  FOREIGN key (pool_id) REFERENCES pool(id) ON DELETE CASCADE,
  FOREIGN key (block_id) REFERENCES block(id) ON DELETE CASCADE,
  FOREIGN key (evm_event_id) REFERENCES evm_event(id) ON DELETE CASCADE,

  CONSTRAINT pool_block_reserves UNIQUE (block_id, pool_id)
);

CREATE INDEX IF NOT EXISTS reserved_block_id_idx ON reserved_raw(block_id);
CREATE INDEX IF NOT EXISTS reserved_pool_id_idx ON reserved_raw(pool_id);
CREATE INDEX IF NOT EXISTS reserved_evm_event_id_idx ON reserved_raw(evm_event_id);
CREATE INDEX IF NOT EXISTS reserved_timestamp_idx ON reserved_raw(timestamp);


CREATE TABLE IF NOT EXISTS volume_raw(
  id Serial PRIMARY KEY,
  
  block_id INT NOT NULL,
  pool_id INT NOT NULL,
  
  volume_1 NUMERIC NOT NULL,
  volume_2 NUMERIC NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL,
  
  FOREIGN key (pool_id) REFERENCES pool(id) ON DELETE CASCADE,
  FOREIGN key (block_id) REFERENCES block(id) ON DELETE CASCADE,
  FOREIGN key (evm_event_id) REFERENCES evm_event(id) ON DELETE CASCADE,

  CONSTRAINT pool_block_volume UNIQUE (block_id, pool_id)
);

CREATE INDEX IF NOT EXISTS volume_raw_block_id_idx ON volume_raw(block_id);
CREATE INDEX IF NOT EXISTS volume_raw_pool_id_idx ON volume_raw(pool_id);
CREATE INDEX IF NOT EXISTS volume_raw_evm_event_id_idx ON volume_raw(evm_event_id);
CREATE INDEX IF NOT EXISTS volume_raw_timestamp_idx ON volume_raw(timestamp);


CREATE TABLE IF NOT EXISTS pool_token(
  id Serial PRIMARY KEY,

  block_id INT NOT NULL,  
  pool_id INT NOT NULL,
  evm_event_id INT, -- Optional link to evm event


  signer_address CHAR(42), -- Optional link to signer address if type is 'User'
  supply NUMERIC NOT NULL,
  type tokenholdertype NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL,

  FOREIGN key (block_id) REFERENCES block(id) ON DELETE CASCADE,
  FOREIGN key (pool_id) REFERENCES pool(id) ON DELETE CASCADE,
  FOREIGN key (evm_event_id) REFERENCES evm_event(id) ON DELETE CASCADE,
  FOREIGN key (signer_address) REFERENCES account(address) ON DELETE CASCADE,

  CONSTRAINT pool_block_signer_type_token UNIQUE (block_id, pool_id, signer_address, type)
);

CREATE INDEX IF NOT EXISTS pool_token_type_idx ON pool_token(type); 
CREATE INDEX IF NOT EXISTS pool_token_pool_id_idx ON pool_token(pool_id);
CREATE INDEX IF NOT EXISTS pool_token_block_id_idx ON pool_token(block_id);
CREATE INDEX IF NOT EXISTS pool_token_timestamp_idx ON pool_token(timestamp);
CREATE INDEX IF NOT EXISTS pool_token_evm_event_id_idx ON pool_token(evm_event_id);
CREATE INDEX IF NOT EXISTS pool_token_signer_address_idx ON pool_token(signer_address);


-- New views
-- Function applies date trunc over timestamp, which we can use in window functions
CREATE OR REPLACE FUNCTION volume_prepare_raw (duration text)
  RETURNS TABLE (
    pool_id INT,
    volume_1 NUMERIC,
    volume_2 NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
      SELECT 
        pool_id,
        volume_1,
        volume_2,
        date_trunc(duration, timestamp)
      FROM volume_raw
      ORDER BY timestamp;
  END; $$ 
LANGUAGE plpgsql;

-- Applying window function over volume_prepare_raw function
-- Volume is calculated as sum of volume_1 and volume_2
CREATE OR REPLACE FUNCTION volume_window_raw (duration text)
  RETURNS TABLE (
    pool_id INT,
    volume_1 NUMERIC,
    volume_2 NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
   SELECT
      v.pool_id,
      SUM(v.volume_1) OVER w,
      SUM(v.volume_2) OVER w,
      v.timeframe
    FROM volume_prepare_raw(duration) AS v
    WINDOW w AS (PARTITION BY v.pool_id, v.timeframe ORDER BY v.timeframe, v.pool_id);
  END; $$ 
LANGUAGE plpgsql;

CREATE OR REPLACE VIEW volume_raw_min AS SELECT * FROM volume_window_raw('minute');
CREATE OR REPLACE VIEW volume_raw_hour AS SELECT * FROM volume_window_raw('hour');
CREATE OR REPLACE VIEW volume_raw_day AS SELECT * FROM volume_window_raw('day');
CREATE OR REPLACE VIEW volume_raw_week AS SELECT * FROM volume_window_raw('week');

-- Function applies date trunc over timestamp, which we can use in window functions
CREATE OR REPLACE FUNCTION reserved_prepare_raw (duration text)
  RETURNS TABLE (
    pool_id INT,
    reserved_1 NUMERIC,
    reserved_2 NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT 
      pool_id,
      reserved_1,
      reserved_2,
      date_trunc(duration, timestamp)
    FROM reserved_raw
    ORDER BY timestamp;
  END; $$ 
LANGUAGE plpgsql;

-- Applying window function over reserved_prepare_raw function
-- last reserved values are used as reserve
CREATE OR REPLACE FUNCTION reserved_window_raw (duration text)
  RETURNS TABLE (
    pool_id INT,
    reserved_1 NUMERIC,
    reserved_2 NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
   SELECT
      l.pool_id,
      LAST(l.reserved_1) OVER w,
      LAST(l.reserved_2) OVER w,
      l.timeframe
    FROM reserved_prepare_raw(duration) AS l
    WINDOW w AS (PARTITION BY l.pool_id, l.timeframe ORDER BY l.timeframe, l.pool_id);
  END; $$ 
LANGUAGE plpgsql;

CREATE OR REPLACE VIEW reserved_raw_min AS SELECT * FROM reserved_window_raw('minute');
CREATE OR REPLACE VIEW reserved_raw_hour AS SELECT * FROM reserved_window_raw('hour');
CREATE OR REPLACE VIEW reserved_raw_day AS SELECT * FROM reserved_window_raw('day');
CREATE OR REPLACE VIEW reserved_raw_week AS SELECT * FROM reserved_window_raw('week');

-- Function applies date trunc over timestamp, which we can use in window functions
CREATE OR REPLACE FUNCTION token_price_prepare (duration text)
  RETURNS TABLE (
    token_address INT,
    price NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT 
      pool_id,
      price,
      date_trunc(duration, timestamp)
    FROM pool_token
    ORDER BY timestamp;
  END; $$ 
LANGUAGE plpgsql;

-- Applying window function over price_prepare function
-- Price is calculated as last price in pool
CREATE OR REPLACE FUNCTION token_price_window (duration text)
  RETURNS TABLE (
    pool_id INT,
    price NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT
      p.pool_id,
      LAST(p.price) OVER w,
      p.timeframe
    FROM token_price_prepare(duration) AS p
    WINDOW w AS (PARTITION BY p.pool_id, p.timeframe ORDER BY p.timeframe, p.pool_id);
  END; $$ 
LANGUAGE plpgsql;

CREATE OR REPLACE VIEW token_price_min AS SELECT * FROM token_price_window('minute');
CREATE OR REPLACE VIEW token_price_hour AS SELECT * FROM token_price_window('hour');
CREATE OR REPLACE VIEW token_price_day AS SELECT * FROM token_price_window('day');
CREATE OR REPLACE VIEW token_price_week AS SELECT * FROM token_price_window('week');

-- Calling volume window raw and multiplying volumes by 0.3% to get a fee
CREATE OR REPLACE VIEW fee_raw AS 
  SELECT
    pool_id,
    block_id,
    volume_1 * 0.0003 AS fee_1,
    volume_2 * 0.0003 AS fee_2,
    timestamp
  FROM volume_raw;

CREATE OR REPLACE FUNCTION fee_prepare_raw (duration text)
  RETURNS TABLE (
    pool_id INT,
    fee_1 NUMERIC,
    fee_2 NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT 
      pool_id,
      fee_1,
      fee_2,
      date_trunc(duration, timestamp)
    FROM fee_raw
    ORDER BY timestamp;
  END; $$ 
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fee_window_raw (duration text)
  RETURNS TABLE (
    pool_id INT,
    fee_1 NUMERIC,
    fee_2 NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT
      f.pool_id,
      SUM(f.fee_1) OVER w,
      SUM(f.fee_2) OVER w,
      f.timeframe
    FROM fee_prepare_raw(duration) AS f
    WINDOW w AS (PARTITION BY f.pool_id, f.timeframe ORDER BY f.timeframe, f.pool_id);
  END; $$ 
LANGUAGE plpgsql;

CREATE OR REPLACE VIEW fee_raw_min AS SELECT * FROM fee_window_raw('minute');
CREATE OR REPLACE VIEW fee_raw_hour AS SELECT * FROM fee_window_raw('hour');
CREATE OR REPLACE VIEW fee_raw_day AS SELECT * FROM fee_window_raw('day');
CREATE OR REPLACE VIEW fee_raw_week AS SELECT * FROM fee_window_raw('week');


-- Function applies date trunc over timestamp, which we can use in window functions
CREATE OR REPLACE FUNCTION candlestick_prepare (duration text)
  RETURNS TABLE (
    pool_id INT,
    open NUMERIC,
    high NUMERIC,
    low NUMERIC,
    close NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT 
      pool_id,
      open,
      high,
      low,
      close,
      date_trunc(duration, timestamp)
    FROM pool_token
    ORDER BY timestamp;
  END; $$ 
LANGUAGE plpgsql;

-- Applying window function over candlestick_prepare function extracting open, high, low, close
CREATE OR REPLACE FUNCTION candlestick_window (duration text)
  RETURNS TABLE (
    pool_id INT,
    token_address CHAR(42), 
    open NUMERIC,
    high NUMERIC,
    low NUMERIC,
    close NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT
      c.pool_id,
      c.token_address,
      FIRST(c.open) OVER w,
      MAX(c.high) OVER w,
      MIN(c.low) OVER w,
      LAST(c.close) OVER w,
      c.timeframe
    FROM candlestick_prepare(duration) AS c
    WINDOW w AS (PARTITION BY c.pool_id, c.token_address, c.timeframe ORDER BY c.pool_id, c.token_address, c.timeframe);
  END; $$ 
LANGUAGE plpgsql;

CREATE OR REPLACE VIEW candlestick_min AS 
  SELECT * FROM candlestick_window('minute');
CREATE OR REPLACE VIEW candlestick_hour AS 
  SELECT * FROM candlestick_window('hour');
CREATE OR REPLACE VIEW candlestick_day AS 
  SELECT * FROM candlestick_window('day');
CREATE OR REPLACE VIEW candlestick_week AS 
  SELECT * FROM candlestick_window('week');

-- Pool volume combined with price for each pool and block
CREATE OR REPLACE VIEW volume AS
  SELECT 
    vl.block_id,
    vl.pool_id,
    vl.timestamp,
    vl.volume_1 * tp1.price + vl.volume_2 * tp2.price AS volume
  FROM volume_raw AS vl
  JOIN pool AS p ON 
    vl.pool_id = p.id
  JOIN token_price as tp1 ON 
    p.token_1 = tp1.token_address AND
    vl.block_id = tp1.block_id
  JOIN token_price as tp2 ON
    p.token_2 = tp2.token_address AND
    vl.block_id = tp2.block_id;

-- Preparing pool volume for window aggregation through date trunc
CREATE OR REPLACE FUNCTION volume_prepare (duration text)
  RETURNS TABLE (
    pool_id INT,
    volume NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
  SELECT 
    pool_id,
    volume,
    date_trunc(duration, timestamp)
  FROM volume;
  END; $$ 
LANGUAGE plpgsql;

-- Applying window function over pool_volume_prepare function and summing volume
CREATE OR REPLACE FUNCTION volume_window (duration text)
  RETURNS TABLE (
    pool_id INT,
    volume NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT
      p.pool_id,
      SUM(p.volume) OVER w,
      p.timeframe
    FROM volume_prepare(duration) AS p
    WINDOW w AS (PARTITION BY p.pool_id, p.timeframe ORDER BY p.timeframe, p.pool_id);
  END; $$ 
LANGUAGE plpgsql;

-- Pool volume combined with price for minute, hour, day, week
CREATE OR REPLACE VIEW volume_min AS SELECT * FROM volume_window('minute');
CREATE OR REPLACE VIEW volume_hour AS SELECT * FROM volume_window('hour');
CREATE OR REPLACE VIEW volume_day AS SELECT * FROM volume_window('day');
CREATE OR REPLACE VIEW volume_week AS SELECT * FROM volume_window('week');

-- Pool reserved supply combined with price for each pool and block
CREATE OR REPLACE VIEW reserved AS
  SELECT 
    l.block_id,
    l.pool_id,
    l.timestamp,
    l.reserved_1 * tp1.price + l.reserved_2 * tp2.price AS reserved
  FROM reserved_raw as l
  JOIN pool as p ON
    l.pool_id = p.id
  JOIN token_price as tp1 ON
    p.token_1 = tp1.token_address AND
    l.block_id = tp1.block_id
  JOIN token_price as tp2 ON
    p.token_2 = tp2.token_address AND
    l.block_id = tp2.block_id;

-- Preparing pool reserved supply for window aggregation through date trunc
CREATE OR REPLACE FUNCTION reserved_prepare (duration text)
  RETURNS TABLE (
    pool_id INT,
    reserved NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT 
      pool_id,
      reserved,
      date_trunc(duration, timestamp)
    FROM reserved
    ORDER BY timestamp;
  END; $$ 
LANGUAGE plpgsql;

-- Applying window function over pool_reserved_prepare function and summing reserved
CREATE OR REPLACE FUNCTION reserved_window (duration text)
  RETURNS TABLE (
    pool_id INT,
    reserved NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT
      p.pool_id,
      LAST(p.reserved) OVER w,
      p.timeframe
    FROM reserved_prepare(duration) AS p
    WINDOW w AS (PARTITION BY p.pool_id, p.timeframe ORDER BY p.timeframe, p.pool_id);
  END; $$ 
LANGUAGE plpgsql;

-- Pool reserved supply combined with price for minute, hour, day, week
CREATE OR REPLACE VIEW reserved_min AS SELECT * FROM reserved_window('minute');
CREATE OR REPLACE VIEW reserved_hour AS SELECT * FROM reserved_window('hour');
CREATE OR REPLACE VIEW reserved_day AS SELECT * FROM reserved_window('day');
CREATE OR REPLACE VIEW reserved_week AS SELECT * FROM reserved_window('week');

-- Pool fees combined with price for each pool and block
CREATE OR REPLACE FUNCTION fee_prepare (duration text)
  RETURNS TABLE (
    pool_id INT,
    fee NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT 
      pool_id,
      fee,
      date_trunc(duration, timestamp)
    FROM fee
    ORDER BY timestamp;
  END; $$ 
LANGUAGE plpgsql;

-- Applying window function over pool_fee_prepare function and summing fee
CREATE OR REPLACE FUNCTION fee_window (duration text)
  RETURNS TABLE (
    pool_id INT,
    fee NUMERIC,
    timeframe TIMESTAMPTZ
  ) AS $$
  BEGIN RETURN QUERY
    SELECT
      p.pool_id,
      SUM(p.fee) OVER w,
      p.timeframe
    FROM fee_prepare(duration) AS p
    WINDOW w AS (PARTITION BY p.pool_id, p.timeframe ORDER BY p.timeframe, p.pool_id);
  END; $$ 
LANGUAGE plpgsql;

-- Pool fees combined with price for minute, hour, day, week
CREATE OR REPLACE VIEW fee_min AS SELECT * FROM fee_window('minute');
CREATE OR REPLACE VIEW fee_hour AS SELECT * FROM fee_window('hour');
CREATE OR REPLACE VIEW fee_day AS SELECT * FROM fee_window('day');
CREATE OR REPLACE VIEW fee_week AS SELECT * FROM fee_window('week');

-- Calculating change between current and previou value
CREATE OR REPLACE FUNCTION change (currentAmount NUMERIC, previousAmount NUMERIC)
  RETURNS NUMERIC AS $$
  BEGIN RETURN
    CASE
      WHEN (previousAmount = 0 OR previousAmount IS NULL) AND currentAmount = 0 
        THEN 0
      WHEN (previousAmount = 0 OR previousAmount IS NULL)
        THEN 100
      ELSE (currentAmount - previousAmount) / previousAmount * 100
    END;
  END; $$ 
LANGUAGE plpgsql;

-- Volume change for each pool and block
CREATE OR REPLACE VIEW volume_change AS
  SELECT
    curr.block_id,
    curr.pool_id,
    curr.timestamp,
    change(curr.volume, prev.volume) AS change
  FROM volume AS curr
  INNER JOIN volume AS prev ON
    curr.pool_id = prev.pool_id AND
    curr.block_id = prev.block_id + 1;

-- Minute volume change for each pool and timestamp
CREATE OR REPLACE VIEW volume_change_min AS 
  SELECT
    pool_id,
    timeframe,
    change(volume, LAG(volume) OVER (ORDER BY timeframe)) AS change
  FROM volume_min;

-- Hour volume change for each pool and timestamp
CREATE OR REPLACE VIEW volume_change_hour AS 
  SELECT
    pool_id,
    timeframe,
    change(volume, LAG(volume) OVER (ORDER BY timeframe)) AS change
  FROM volume_hour;

-- Day volume change for each pool and timestamp
CREATE OR REPLACE VIEW volume_change_day AS 
  SELECT
    pool_id,
    timeframe,
    change(volume, LAG(volume) OVER (ORDER BY timeframe)) AS change
  FROM volume_day;

-- Week volume change for each pool and timestamp
CREATE OR REPLACE VIEW volume_change_week AS 
  SELECT
    pool_id,
    timeframe,
    change(volume, LAG(volume) OVER (ORDER BY timeframe)) AS change
  FROM volume_week;


-- User pool share
CREATE OR REPLACE VIEW user_pool_share AS
  SELECT
    upt.pool_id,
    upt.block_id,
    upt.timestamp,
    CASE 
      WHEN upt.supply <= 0 THEN 0
      ELSE upt.supply / pt.supply
    END AS share
  FROM pool_token AS upt
  INNER JOIN pool_token AS pt ON
    upt.pool_id = pt.pool_id AND
    upt.block_id = pt.block_id
  WHERE upt.type = 'Account' AND pt.type = 'Contract';
