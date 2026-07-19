export const authV3AppContract = {
  userNamespace: "$users",
  providerIDs: ["magic-code", "apple", "google", "github", "enterprise-oidc"],
  statuses: {
    signedIn: "signedIn",
    relaunched: "signedIn",
    signedOut: "signedOut",
  },
  rejectionCode: "authFailed",
} as const;
