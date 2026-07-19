import assert from "node:assert/strict";
import test from "node:test";

import { authV3AppContract } from "./auth-v3-app-contract.js";

test("Auth V3 app contract preserves the exact app-owned lifecycle shape", () => {
  assert.deepEqual(authV3AppContract, {
    userNamespace: "$users",
    providerIDs: ["magic-code", "apple", "google", "github", "enterprise-oidc"],
    statuses: {
      signedIn: "signedIn",
      relaunched: "signedIn",
      signedOut: "signedOut",
    },
    rejectionCode: "authFailed",
  });
});
