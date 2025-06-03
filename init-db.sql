DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS users;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    password VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    lastName VARCHAR(255),
    email VARCHAR(255) UNIQUE NOT NULL
);

INSERT INTO users (password, email, name, lastName) 
VALUES ('$2y$10$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', 'admin@example.com', 'Admin', 'User');

CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    userIdSend TEXT NOT NULL,
    userIdReceive TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
