export type PreferencesDownloadedFile = {
  name: string;
  contentType: string;
  bytes: number[];
  shouldClear: boolean;
};

export type PreferencesContract = {
  swiftUserID: string;
  phaseSequence: ["connected", "authenticated"];
  streamContent: "hello-stream";
  downloadedFiles: [PreferencesDownloadedFile, PreferencesDownloadedFile];
};

export function preferencesContract(input: {
  swiftUserID: string;
}): PreferencesContract {
  return {
    swiftUserID: input.swiftUserID,
    phaseSequence: ["connected", "authenticated"],
    streamContent: "hello-stream",
    downloadedFiles: [
      {
        name: "recording.m4a",
        contentType: "audio/mp4",
        bytes: [0, 1, 2, 3],
        shouldClear: true,
      },
      {
        name: "transcript.txt",
        contentType: "text/plain",
        bytes: [4, 5, 6],
        shouldClear: false,
      },
    ],
  };
}
