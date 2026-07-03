# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability within env.zig, please [create a GitHub issue](https://github.com/muhammad-fiaz/env.zig/issues/new?template=bug_report.md). All security vulnerabilities will be promptly addressed.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.0.x   | :white_check_mark: |

## Security Best Practices

When using env.zig:

1. Never commit `.env` files containing secrets to version control
2. Use `.gitignore` to exclude `.env` files
3. Use schema validation to ensure required configuration is present
4. Validate input values before using them in security-sensitive contexts
