# Signing and the "could not verify" dialog

macOS shows this when it cannot check an app with Apple:

> **"Sieve" Not Opened** — Apple could not verify "Sieve" is free of malware that may harm
> your Mac or compromise your privacy.  *[Move to Trash] [Done]*

Nothing was scanned and nothing was found. It is a statement about the signature, not the
code. There are three levels, and which one a build lands on decides who sees that dialog.

| Signature | Costs | Dialog on your own Mac | Dialog on a stranger's Mac |
| --- | --- | --- | --- |
| **ad-hoc** (`--sign -`) | nothing | **yes**, every build | **yes**, every build |
| **Apple Development** | free with any Apple ID | **no** | probably yes — unverified |
| **Developer ID** + notarised | $99/year | no | **no** |

`build_app.sh` picks the best available automatically and prints which it used.

## Why every release re-triggers it

Gatekeeper remembers an approval by the app's code hash, and that hash changes with every
build. So approving version 1.4 does nothing for 1.4.1 — with an ad-hoc signature each
release has to be approved again. That is the real reason this kept coming back.

## Apple Development — the free half-fix

If you have ever signed into Xcode with an Apple ID you already have one:

```sh
security find-identity -v -p codesigning
```

`build_app.sh` finds it and uses it with no configuration. A quarantined build signed this
way was verified to open from Finder with no dialog on the machine holding the certificate.

The limit is real: **Apple Development is a development certificate, not a distribution
one.** It has not been checked on a Mac that does not hold the certificate, and Apple's
documentation does not promise it will pass there. Assume people downloading from the
releases page still see the dialog.

The certificate expires about a year after it is issued. Regenerate it in Xcode →
Settings → Accounts → Manage Certificates when it does.

## Developer ID and notarisation — the only complete fix

This needs the [Apple Developer Program](https://developer.apple.com/programs/), $99/year.
With it, nobody ever sees the dialog again.

**Once:**

1. Join the programme, then in Xcode → Settings → Accounts → Manage Certificates, add a
   **Developer ID Application** certificate.
2. Make an app-specific password at [appleid.apple.com](https://appleid.apple.com) →
   Sign-In and Security → App-Specific Passwords.
3. Store the credentials once:

   ```sh
   xcrun notarytool store-credentials sieve-notary \
     --apple-id "you@example.com" \
     --team-id "YOURTEAMID" \
     --password "abcd-efgh-ijkl-mnop"
   ```

**Then per release:**

```sh
./build_app.sh 1.5          # finds the Developer ID automatically
./make_dmg.sh 1.5           # notarises and staples if SIEVE_NOTARY_PROFILE is set
```

```sh
export SIEVE_NOTARY_PROFILE=sieve-notary
```

Notarisation takes a few minutes. `make_dmg.sh` submits the image, waits, and staples the
ticket so it validates offline afterwards. Verify with:

```sh
spctl -a -vvv -t install Sieve-1.5.dmg     # should say: accepted, source=Notarized Developer ID
xcrun stapler validate Sieve-1.5.dmg
```

## Until then

The install commands in the README sidestep the dialog by clearing the download flag, and
the disk image carries click-by-click instructions for people who do not use Terminal.
