# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Edge AI Lab, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email: **security@andrewvoirol.com**

You should receive a response within 48 hours. If for some reason you do not, please follow up to ensure we received your original message.

## Scope

Edge AI Lab runs entirely on-device. There are no backend servers, user accounts, or cloud data transmission. The primary security-relevant areas are:

- **Model file loading** — The app loads `.litertlm` model files from user-specified directories
- **MCP server support** — The app can launch local subprocess-based MCP servers via stdio JSON-RPC
- **HuggingFace downloads** — Model downloads use HTTPS and are user-initiated
- **Kaggle downloads** — Kaggle model downloads use HTTPS with API key authentication
- **Credential storage** — HuggingFace tokens and Kaggle API keys are stored in the macOS/iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **App Sandbox** — The macOS app runs with the sandbox disabled (see [README](README.md#security) for rationale)

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 2.0.x   | ✅ Current release |
| 1.0.x   | ✅ Security fixes  |

## Disclosure Policy

We follow [coordinated disclosure](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure). We ask that you:

1. Allow us reasonable time to investigate and address the issue
2. Avoid exploiting the vulnerability beyond what is necessary to demonstrate it
3. Do not disclose the issue publicly until we have released a fix

Thank you for helping keep Edge AI Lab and its users safe.
