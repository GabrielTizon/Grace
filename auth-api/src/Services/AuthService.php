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
            $this->redis->setex($cacheKey, 3600, json_encode(['username' => $username]));
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
            $this->redis->setex($cacheKey, 3600, $jwt);
            return ['token' => $jwt];
        }
        return ['error' => 'Invalid credentials'];
    }

    public function getUser($username) {
        $user = $this->userModel->findByUsername($username);
        if ($user) {
            unset($user['password']);
            return $user;
        }
        return ['error' => 'User not found'];
    }

    public function updatePassword($username, $password) {
        $passwordHash = password_hash($password, PASSWORD_BCRYPT);
        $updated = $this->userModel->updatePassword($username, $passwordHash);
        if ($updated) {
            return ['message' => 'Password updated'];
        }
        return ['error' => 'Update failed'];
    }

    public function deleteUser($username) {
        $deleted = $this->userModel->delete($username);
        if ($deleted) {
            return ['message' => 'User deleted'];
        }
        return ['error' => 'Delete failed'];
    }
}