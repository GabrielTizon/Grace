<?php
require '/app/vendor/autoload.php';

use Firebase\JWT\JWT;

header('Content-Type: application/json');

$dsn = "pgsql:host=db;port=5432;dbname=mydb;user=user;password=password";
try {
    $pdo = new PDO($dsn);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Database connection failed: ' . $e->getMessage()]);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_SERVER['REQUEST_URI']) && strpos($_SERVER['REQUEST_URI'], '/register') !== false) {
    if (!isset($input['username'], $input['password'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Username and password required']);
        exit;
    }

    $username = $input['username'];
    $password = password_hash($input['password'], PASSWORD_BCRYPT);

    try {
        $stmt = $pdo->prepare("INSERT INTO users (username, password) VALUES (?, ?)");
        if ($stmt->execute([$username, $password])) {
            $payload = ['username' => $username, 'exp' => time() + 3600];
            $jwt = JWT::encode($payload, 'your_secret_key', 'HS256');
            echo json_encode(['token' => $jwt]);
        } else {
            http_response_code(400);
            echo json_encode(['error' => 'Registration failed']);
        }
    } catch (PDOException $e) {
        if (strpos($e->getMessage(), 'duplicate key') !== false) {
            http_response_code(400);
            echo json_encode(['error' => 'Username already exists']);
        } else {
            http_response_code(500);
            echo json_encode(['error' => 'Database error: ' . $e->getMessage()]);
        }
    }
} else {
    http_response_code(404);
    echo json_encode(['error' => 'File not found', 'uri' => $_SERVER['REQUEST_URI'] ?? 'unknown']);
}