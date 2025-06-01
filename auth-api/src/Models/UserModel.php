<?php
namespace Models;

class UserModel {
    private $pdo;

    public function __construct($pdo) {
        $this->pdo = $pdo;
    }

    public function create($username, $password) {
        $stmt = $this->pdo->prepare("INSERT INTO users (username, password) VALUES (?, ?)");
        $stmt->execute([$username, $password]);
    }

    public function findByUsername($username) {
        $stmt = $this->pdo->prepare("SELECT * FROM users WHERE username = ?");
        $stmt->execute([$username]);
        return $stmt->fetch();
    }

    public function updatePassword($username, $password) {
        $stmt = $this->pdo->prepare("UPDATE users SET password = ? WHERE username = ?");
        return $stmt->execute([$password, $username]);
    }

    public function delete($username) {
        $stmt = $this->pdo->prepare("DELETE FROM users WHERE username = ?");
        return $stmt->execute([$username]);
    }
}