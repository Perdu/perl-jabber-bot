DROP DATABASE IF EXISTS anu;
CREATE DATABASE anu CHARACTER SET utf8 COLLATE utf8_general_ci;
connect anu;

-- contains a copy of all score at every timestamp (download)
CREATE TABLE `quotes` (
       quote_id int(3) NOT NULL AUTO_INCREMENT,
       author varchar(100) NOT NULL,
       details varchar(100),
       quote varchar(10000) NOT NULL,
       `timestamp` timestamp DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`quote_id`)
) DEFAULT CHARSET=utf8;

CREATE TABLE `words_in_quote` (
       quote_id int(3) NOT NULL,
       word varchar(50) NOT NULL,
       PRIMARY KEY (`quote_id`, `word`),
       FOREIGN KEY (`quote_id`) REFERENCES `quotes`(`quote_id`)
) DEFAULT CHARSET=utf8;

CREATE TABLE `words_links` (
       word1 varchar(50) NOT NULL,
       word2 varchar(50) NOT NULL,
       occurences int(5) NOT NULL,
       PRIMARY KEY (`word1`, `word2`)
) DEFAULT CHARSET=utf8;
