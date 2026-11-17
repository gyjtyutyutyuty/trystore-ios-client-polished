# App Attest implementation references

## Apple protocol requirements

Apple requires the app to obtain a unique, one-time server challenge before submitting attestation or assertion data. The server must retain the challenge and reject expiration or reuse. Attestation verification includes decoding the CBOR object, validating the `x5c` certificate chain against Apple’s App Attest root, checking the nonce extension against SHA-256 of authenticator data plus the client-data hash, matching the public-key-derived key ID, validating the App ID hash and environment AAGUID, and requiring an initial counter of zero. Assertion verification binds the signed client data to the request, validates the App ID hash and signature, and requires a strictly increasing counter. The server must persist the latest counter.

For `DCAppAttestService`, the client checks `isSupported`, calls `generateKey`, obtains an attestation with `attestKey(_:clientDataHash:)`, and generates request assertions with `generateAssertion(_:clientDataHash:)`. The key identifier must be persisted for subsequent operations. App Attest proves integrity signals for a genuine app instance; it does not make client-side data or checks tamper-proof and does not establish user identity.

## Sources

- [Apple, Validating apps that connect to your server](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server)
- [Apple, Establishing your app’s integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)
- [Apple, Attestation Object Validation Guide](https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide)
- [Apple, DCAppAttestService](https://developer.apple.com/documentation/devicecheck/dcappattestservice)
- [Bradford Tech, supabase-integrity-attest](https://github.com/bradford-tech/supabase-integrity-attest) — MIT-licensed edge-runtime verifier, inspected at version 0.9.1. It supplies cryptographic object verification only; this application still implements license/device binding, challenge storage, one-time consumption, and atomic counter updates.

## Configuration gate

The registered App ID prefix must be confirmed from Apple Developer Certificates, Identifiers & Profiles. The repository’s Xcode project establishes the Bundle ID `cc.forcequit.worse-query` and Team ID `K976G5HK7K`, but the App ID prefix is not inferred from the Team ID. Production deployment must set the exact `APP_ATTEST_APP_ID` and `APP_ATTEST_ENVIRONMENT=production` on the license Worker. The corresponding app identifier must have App Attest enabled and the provisioning profile must carry the environment entitlement. Missing or inconsistent configuration is a hard failure.
