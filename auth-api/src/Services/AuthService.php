<?php
namespace Services;
use Firebase\JWT\JWT;
use Models\UserModel;

class AuthService {
    private $pdo;
    private $redis;
    private $userModel;
    private $jwtSecret = 'secret_key';

    public function __construct($pdo, $redis) {
        $this->pdo = $pdo;
        $this->redis = $redis;
        $this->userModel = new UserModel($pdo);
    }

    public function register($username, $password) {
        $cacheKey = "user:$username";
        if ($this->redis->exists($cacheKey)) {
            return ['message' => 'User already registered (cached)'];
        }

        try {
            $passwordHash = password_hash($password, PASSWORD_BCRYPT);
            $this->userModel->create($username, $passwordHash);
            $this->redis->set($cacheKey, json_encode(['username' => $username]), 'EX', 3600);
            return ['message' => 'User registered'];
        } catch (\Exception $e) {
            return ['error' => 'Registration failed: ' . $e->getMessage()];
        }
    }

    public function login($username, $password) {
        $cacheKey = "token:$username";
        $cachedToken = $this->redis->get($cacheKey);
        if ($cachedToken) {
            return ['token' => $cachedToken];
        }

        $user = $this->userModel->findByUsername($username);
        if ($user && password_verify($password, $user['password'])) {
            $payload = ['username' => $username];
            $jwt = JWT::encode($payload, $this->jwtSecret, 'HS256');
            $this->redis->set($cacheKey, $jwt, 'EX', 3600);
            return ['token' => $jwt];
        }
        return ['error' => 'Invalid credentials'];
    }
}