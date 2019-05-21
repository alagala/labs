USE tweetsdb
GO

-- You may use partitioned tables and indexes to
-- parallelize the write throughput from
-- Azure Stream Analytics

-- CREATE PARTITION FUNCTION partition_by_user_id(BIGINT)
-- AS RANGE LEFT FOR VALUES (...);

-- CREATE PARTITION SCHEME hash_by_value
-- AS PARTITION partition_by_user_id
-- ALL TO ([PRIMARY]);
-- GO

DROP TABLE IF EXISTS tweets
CREATE TABLE tweets
(
    id BIGINT NOT NULL ,
    created_at DATETIME NOT NULL,
    tweet NVARCHAR(200) NOT NULL,
    source NVARCHAR(160) NOT NULL,
    user_id BIGINT NOT NULL,
    user_name NVARCHAR(50) NOT NULL,
    user_screen_name NVARCHAR(50) NOT NULL,
    CONSTRAINT pk_tweets PRIMARY KEY CLUSTERED (id ASC)
)
-- ON hash_by_value(id);
GO

SELECT * FROM tweets
GO