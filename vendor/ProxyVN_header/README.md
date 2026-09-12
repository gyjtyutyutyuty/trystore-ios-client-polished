# ProxyVN header archive

This directory preserves the encrypted `ProxyVN_header.zip` input as a **separate, non-build component**. The files are generated Objective-C interface headers from a class-dump and are not referenced by the TryStore Xcode target.

The archive includes names associated with exploit, memory, patch-byte, overlay, and authentication components. It is retained for provenance/review only; no implementation binaries or source were supplied, and no code from this directory is linked into the application.
