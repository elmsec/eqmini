# Security

Report vulnerabilities privately to **can_0x@elma.dev**. Include affected versions, reproduction steps, and the likely impact. Please avoid public issues for vulnerabilities until a fix is available. There is no guaranteed response time or bug bounty.

The latest preview is the only maintained version. Download only from the project's releases or build from source.

Audio is processed locally in memory. The app has no server, analytics, updater, privileged helper, or audio-recording feature. macOS audio-capture permission is required even though audio is not saved. Diagnostic commands can print app names, bundle identifiers, and process IDs to the terminal; inspect them before sharing.

Certificates, private keys, notarization credentials, and local preferences must never be committed. The CI workflow has read-only repository permissions and does not publish releases or access signing credentials.
