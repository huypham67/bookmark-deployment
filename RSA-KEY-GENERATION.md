# RSA Key Generation Guide for JWT

This guide explains how to generate the RSA private and public keys required for JWT authentication in the bookmark-service application.

## Prerequisites

- OpenSSL installed on your system (usually pre-installed on Linux/Mac)
- SSH access to your VM

## Generation Steps

### 1. SSH into the VM

```bash
ssh your-user@your-vm-ip
```

### 2. Navigate to the deployment directory

```bash
cd /path/to/deployment
```

### 3. Create the keys directory structure

```bash
mkdir -p bookmark-service/keys
cd bookmark-service/keys
```

### 4. Generate Private Key (2048-bit RSA)

```bash
openssl genrsa -out private.pem 2048
```

This command generates a 2048-bit RSA private key and saves it to `private.pem`.

### 5. Generate Public Key from Private Key

```bash
openssl rsa -in private.pem -pubout -out public.pem
```

This command extracts the public key from the private key and saves it to `public.pem`.

### 6. Verify the keys were created

```bash
ls -la
```

You should see both `private.pem` and `public.pem` files in the `bookmark-service/keys` directory.

### 7. Set appropriate permissions (optional but recommended)

```bash
chmod 600 private.pem
chmod 644 public.pem
```

## Complete Directory Structure

After generating the keys, your deployment directory should look like:

```
deployment/
├── docker-compose.yaml
├── bookmark-service/
│   ├── .env
│   └── keys/
│       ├── private.pem
│       └── public.pem
├── config/
│   └── cloudflared.env
├── nginx/
│   └── nginx.conf
└── postgres/
```

## Verification

To verify your keys are properly formatted:

### View Private Key
```bash
openssl pkey -in private.pem -text -noout | head -3
```

### View Public Key
```bash
openssl pkey -in public.pem -text -noout | head -3
```

## Docker Deployment

Once the keys are in place:

1. The `docker-compose.yaml` is configured to mount the keys directory from `./bookmark-service/keys:/app/keys`
2. When the container starts, it will find the keys at `/app/keys/private.pem` and `/app/keys/public.pem`
3. The application will use these keys for JWT token generation and validation

## Troubleshooting

### Keys not found error

If you see an error like:
```
{"error":"failed to read RSA private key file: open keys/private.pem: no such file or directory"}
```

- Verify the keys exist: `ls -la bookmark-service/keys/`
- Ensure you're running docker-compose from the deployment directory
- Check that the volume mount in docker-compose.yaml is correct

### Permission denied error

If you get permission denied errors:
```bash
chmod 644 bookmark-service/keys/private.pem
chmod 644 bookmark-service/keys/public.pem
```

### Invalid key format error

Regenerate the keys using the steps above. Ensure you're using the correct openssl commands.

## Security Considerations

⚠️ **Important Security Notes:**

1. **Keep private keys secure**: Never commit `private.pem` to version control
2. **Use .gitignore**: Add `bookmark-service/keys/` to `.gitignore` to prevent accidental commits
3. **Restrict access**: Use appropriate file permissions (600 for private key)
4. **Key rotation**: Consider rotating keys periodically in production environments
5. **Backup**: Keep secure backups of your private key

## Regenerating Keys

To regenerate new keys (e.g., for security purposes):

1. Back up existing keys (if needed)
2. Delete old keys: `rm bookmark-service/keys/*.pem`
3. Follow steps 4-5 above to generate new keys
4. Restart the application: `docker-compose restart bookmark-service`

Note: Regenerating keys will invalidate all existing JWT tokens. Users will need to re-login.

---

**Last Updated:** 2026-06-03  
**Applicable Version:** bookmark-service v1.0+

