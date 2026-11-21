# License device binding

The license Worker now binds local `global_keys` activations to the submitted iOS `deviceId`.

- The raw license key is still stored only as an HMAC digest.
- D1 stores `(key_id, device_id)` plus first/last-seen timestamps.
- `max_devices` is enforced server-side; generated keys continue to default to one device.
- Revalidation from the same device remains allowed.
- A new device receives `device_limit` and cannot obtain the patch bundle key.
- Device identifiers are accepted only in canonical UUID form.

## Deploy

Apply `cloudflare/migrations/0001_license_devices.sql` to the D1 database used by the global-control Worker before deploying the updated `cloudflare/license-worker.js`. Existing keys remain active, and the first successful validation after deployment claims their first device.

A support/admin recovery flow should delete a specific row from `license_devices` when a customer legitimately replaces a device. Do not put the signing secret or an admin token in the iOS client.
