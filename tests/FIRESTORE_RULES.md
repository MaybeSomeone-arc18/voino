# Firestore rules tests

`tests/firestore_rules.test.mjs` runs the security rules in
`firestore.rules` against the Firestore emulator (owner-only boards,
cross-user denial, malformed documents, counter regression).

Needs a JDK 21+ and dev deps:

    npm install
    npm run test:rules

The plain JS suite (`node --test tests/*.test.js`) needs no install and
does not include this file.
