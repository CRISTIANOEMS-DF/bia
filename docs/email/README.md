# 🚀 Desafio 1: Imersão AWS & IA - Agosto/2026

Repositório oficial para submissão e documentação de infraestrutura da Imersão AWS & IA.

---

## 🔒 Security & Compliance Notice

A documentação e os comprovantes de conclusão passaram por um rigoroso processo de anonimização e criptografia de ponta.

O comprovante oficial encontra-se anexado no arquivo:
📂 [comprovante_blindado.pdf](./comprovante_blindado.pdf)

---

## 🔑 Access Control & Enigma

O arquivo PDF está protegido por uma senha mestra. A chave de descriptografia não está exposta em texto plano, pois foi processada utilizando uma função de derivação de chave baseada em salt (**PBKDF2-HMAC-SHA256** com 100.000 iterações). 

### Parâmetros do Enigma:
* **Salt Utilizado:** `desafio`
* **Ciphertext / Hash Alvo:** 
  `b7ef1088af2683e1dff6116ea832983ced276b5b78f1e6fdc0e5eedf711576f9`

> **Dica de Ferramenta:** Se quiser testar via linha de comando pura, você pode utilizar o utilitário oficial do [OpenSSL](https://www.openssl.org/) para processar a derivação de chave.
---

## 📋 Wordlist Embutida

Para auxiliar na resolução (ou testar suas habilidades de força bruta/dicionário), utilize o conjunto de strings abaixo como base de testes no seu script de descriptografia:

```text
admin, secret, password, 123456, root, lambda, docker, kubernetes, cloud, security, AWS, terraform, linux, kali, python, hacker, cipher, crypto, network, aws
