import assert from "node:assert/strict";
import test from "node:test";

import { mobileChatV3AppContract } from "./mobile-chat-v3-app-contract.js";

test("Mobile Chat V3 preserves exact canonical cross-SDK shapes", () => {
  assert.deepEqual(mobileChatV3AppContract, {
    upstream: {
      mobile: {
        repository: "https://github.com/betomoedano/instant-realtime-chat",
        revision: "a844b48eacd2669316667cab5ffb8f5548948cf6",
      },
      web: {
        repository: "https://github.com/instantdb/instant-examples",
        revision: "c92c5d236b2ef653502cb951d34a7050ac6b57a0",
      },
    },
    namespaces: {
      files: "$files",
      users: "$users",
      profiles: "profiles",
      channels: "channels",
      messages: "messages",
    },
    links: {
      linkedPrimaryUser: "$usersLinkedPrimaryUser",
      userProfile: "userProfile",
      authorMessages: "authorMessages",
      channelMessages: "channelMessages",
    },
    room: {
      type: "chat",
      swiftPresence: {
        profileId: "mobile-chat-swift-profile",
        displayName: "Swift Chatter",
      },
      typeScriptPresence: {
        profileId: "mobile-chat-typescript-profile",
        displayName: "TypeScript Chatter",
      },
      swiftTyping: { isTyping: true },
      typeScriptTyping: { isTyping: false },
      swiftReaction: { name: "wave", directionAngle: 90, rotationAngle: 180 },
      typeScriptReaction: { name: "heart", directionAngle: 45, rotationAngle: 270 },
    },
    swiftCreated: {
      profile: {
        id: "mobile-chat-swift-profile",
        user: "mobile-chat-swift-user",
        displayName: "Swift Chatter",
      },
      channel: {
        id: "mobile-chat-swift-channel",
        name: "Swift Channel",
      },
      message: {
        id: "mobile-chat-swift-message",
        channel: "mobile-chat-swift-channel",
        author: "mobile-chat-swift-profile",
        content: "Swift live message",
        timestamp: 1_700_000_010_000,
      },
    },
    typeScriptCreated: {
      profile: {
        id: "mobile-chat-typescript-profile",
        user: "mobile-chat-typescript-user",
        displayName: "TypeScript Chatter",
      },
      channel: {
        id: "mobile-chat-typescript-channel",
        name: "TypeScript Channel",
      },
      message: {
        id: "mobile-chat-typescript-message",
        channel: "mobile-chat-typescript-channel",
        author: "mobile-chat-typescript-profile",
        content: "TypeScript live message",
        timestamp: 1_700_000_011_000,
      },
    },
    compilerWarningCount: 0,
  });
});
