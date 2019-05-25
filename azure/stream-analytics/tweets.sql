CREATE TABLE tweets
(
    id BIGINT NOT NULL ,
    created_at DATETIME NOT NULL,
    tweet NVARCHAR(200) NOT NULL,
    source NVARCHAR(160) NOT NULL,
    user_id BIGINT NOT NULL,
    user_name NVARCHAR(50) NOT NULL,
    user_screen_name NVARCHAR(50) NOT NULL
)
WITH
(
    DISTRIBUTION = HASH(user_id),
    CLUSTERED COLUMNSTORE INDEX
)
GO

SELECT * FROM tweets
GO