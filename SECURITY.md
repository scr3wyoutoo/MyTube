# Security Policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature from the repository's **Security** tab when it is available. If it is not enabled, contact the repository owner privately through their GitHub profile before sharing technical details.

Do not open a public issue containing API keys, cookies, authentication headers, signed application packages, device logs, or reproducible private stream URLs.

## Sensitive data

The repository must never contain production credentials or signing material. The optional YouTube Data API key is accepted only through `--dart-define` and must be restricted appropriately. Exported application logs are redacted and bounded, but should still be reviewed before sharing.

## Scope

The project uses unofficial YouTube interfaces and local loopback transport. Availability failures or upstream format changes are not automatically security vulnerabilities, but unexpected credential exposure, unsafe URL handling, arbitrary local-file access, or cross-profile data leakage should be reported privately.
