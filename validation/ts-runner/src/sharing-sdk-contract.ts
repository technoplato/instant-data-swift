import type { InstaQLParams, TxChunk } from "@instantdb/core";

import type { AppSchema } from "../../fixtures/sharing.schema.js";

export function sharingQuery(listID: string) {
  return {
    v3_shared_lists: {
      $: { where: { id: listID } },
      owner: {},
      readers: {},
      writers: {},
      share: {
        owner: {},
        memberships: { user: {} },
      },
    },
  } satisfies InstaQLParams<AppSchema>;
}

export interface SharingOwnerTransactionInput {
  listID: string;
  shareID: string;
  membershipID: string;
  ownerID: string;
  token: string;
  title: string;
  value: number;
  now: Date;
}

export function sharingOwnerTransaction(
  tx: TxChunk<AppSchema>,
  input: SharingOwnerTransactionInput,
) {
  return [
    tx.v3_shared_lists[input.listID]
      .update({ title: input.title, value: input.value })
      .link({ owner: input.ownerID }),
    tx.v3_shares[input.shareID]
      .update({
        token: input.token,
        rootNamespace: "v3_shared_lists",
        rootID: input.listID,
        createdAt: input.now,
        updatedAt: input.now,
      })
      .link({ owner: input.ownerID, root: input.listID }),
    tx.v3_share_memberships[input.membershipID]
      .update({ role: "owner", acceptedAt: input.now })
      .link({ share: input.shareID, user: input.ownerID }),
  ];
}

export type SharingGrantRole = "reader" | "writer";

export interface SharingGrantTransactionInput {
  listID: string;
  shareID: string;
  membershipID: string;
  userID: string;
  role: SharingGrantRole;
  acceptedAt: Date;
}

export function sharingGrantTransaction(
  tx: TxChunk<AppSchema>,
  input: SharingGrantTransactionInput,
) {
  const membership = tx.v3_share_memberships[input.membershipID]
    .update({ role: input.role, acceptedAt: input.acceptedAt })
    .link({ share: input.shareID, user: input.userID });
  const root = input.role === "reader"
    ? tx.v3_shared_lists[input.listID].link({ readers: input.userID })
    : tx.v3_shared_lists[input.listID].link({ writers: input.userID });

  return [membership, root];
}
