# Test fixtures

## `electrum_test_cert.pem` and `electrum_test_key.pem`

A self-signed TLS certificate for `localhost` and its private key, made for
the tests. **Not a secret.** Nothing outside the tests uses them, and the app
never trusts this certificate: it accepts a self-signed certificate only after
the user has pinned it in Settings.

`wallet_history_section_test.dart` serves a fake Electrum server with them on
`127.0.0.1`. That is how it tests the "trust this server's certificate?"
prompt and certificate pinning, which a real home node's self-signed
certificate needs. The test pins the certificate's SHA-256 fingerprint
(`_fingerprint`), so a new pair means updating that constant too.

- Subject: `CN=localhost`, RSA 2048
- Valid 2026-10-31 to 2126-10-07, so it will not expire under the tests
- SHA-256: `37:8D:67:E7:2F:0E:B8:AE:B1:55:3B:93:0A:06:B9:72:5E:C1:21:CC:F4:51:4C:53:0E:16:83:18:87:97:F7:D6`

Secret scanners flag the key, as they should for any committed private key.
`.github/secret_scanning.yml` excludes this folder from GitHub's scanning
(audit P-12). Keep anything that *is* a secret out of it.

To make a new pair:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
  -subj '/CN=localhost' \
  -keyout test/fixtures/electrum_test_key.pem \
  -out test/fixtures/electrum_test_cert.pem
openssl x509 -noout -fingerprint -sha256 -in test/fixtures/electrum_test_cert.pem
```

then put the new fingerprint in `wallet_history_section_test.dart`.
