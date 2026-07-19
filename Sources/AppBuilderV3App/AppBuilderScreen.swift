import AuthV3App
import Foundation
import InstantSwiftData

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public struct AppBuilderV3Screen: View {
    @InstantAuth(AppBuilderV3User.self, providers: AppBuilderV3AuthProviders.self)
    private var auth
    @FetchOne private var user: AppBuilderV3User?

    public init() {}

    public var body: some View {
      Group {
        if let user, user.email?.isEmpty == false {
          AppBuilderV3BuildsScreen(ownerID: user.id)
        } else if auth.user != nil {
          ContentUnavailableView(
            "Email account required",
            systemImage: "envelope.badge",
            description: Text("Sign in with a magic code to generate apps.")
          )
        } else {
          AuthV3LoginScreen()
        }
      }
      .task(id: auth.user?.id) {
        do {
          try await $user.task(userQuery)
        } catch is CancellationError {
        } catch {
        }
      }
    }

    private var userQuery: InstantQuery<AppBuilderV3User>? {
      auth.user.map {
        AppBuilderV3User.query.where(
          InstantAttributePath<AppBuilderV3User, String>("id") == $0.id.rawValue
        )
      }
    }
  }

  @MainActor
  public struct AppBuilderV3BuildsScreen: View {
    @FetchAll private var builds: [AppBuilderV3Build]
    @FetchAll private var files: [AppBuilderV3File]
    @State private var model: AppBuilderV3Model

    public let ownerID: InstantID<AppBuilderV3User>

    public init(
      ownerID: InstantID<AppBuilderV3User>,
      model: AppBuilderV3Model = AppBuilderV3Model()
    ) {
      self.ownerID = ownerID
      _model = State(initialValue: model)
    }

    public var body: some View {
      @Bindable var model = model
      NavigationStack {
        List {
          Section("Generate") {
            TextEditor(text: $model.prompt)
              .frame(minHeight: 100)
            Button("Generate Mini App") {
              Task { await generateButtonTapped() }
            }
            .disabled(
              model.isGenerating
                || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            if model.isGenerating {
              ProgressView()
            }
            Text(model.message)
          }
          Section("Previous Builds") {
            if builds.isEmpty {
              Text("No builds found")
            }
            ForEach(builds) { build in
              NavigationLink {
                AppBuilderV3BuildScreen(buildID: build.id)
              } label: {
                VStack(alignment: .leading) {
                  Text(build.title ?? "Untitled build")
                  Text(build.isPreviewable == true ? "Previewable" : "Not Previewable")
                    .font(.caption)
                }
              }
            }
          }
          Section("Generated Files") {
            if files.isEmpty {
              Text("No generated files")
            }
            ForEach(files) { file in
              LabeledContent(file.path, value: file.url)
            }
          }
        }
        .navigationTitle("App Builder")
      }
      .task(id: ownerID) {
        do {
          try await $builds.task(AppBuilderV3Build.forOwner(ownerID))
        } catch is CancellationError {
        } catch {
        }
      }
      .task {
        do {
          try await $files.task(AppBuilderV3File.ordered)
        } catch is CancellationError {
        } catch {
        }
      }
    }

    private func generateButtonTapped() async {
      await model.generateButtonTapped(ownerID: ownerID)
    }
  }

  @MainActor
  public struct AppBuilderV3BuildScreen: View {
    @FetchOne private var build: AppBuilderV3Build?

    public let buildID: InstantID<AppBuilderV3Build>

    public init(buildID: InstantID<AppBuilderV3Build>) {
      self.buildID = buildID
    }

    public var body: some View {
      Form {
        if let build {
          LabeledContent("Title", value: build.title ?? "Untitled build")
          LabeledContent("Instant app", value: build.instantAppID)
          LabeledContent(
            "Status",
            value: build.isPreviewable == true ? "Previewable" : "Generating"
          )
          if let reasoning = build.reasoning {
            Section("Reasoning") { Text(reasoning) }
          }
          Section("Code") { Text(build.code).textSelection(.enabled) }
          if let file = build.file {
            LabeledContent("Generated file", value: file.rawValue)
          }
        } else {
          ProgressView("Loading build")
        }
      }
      .navigationTitle(build?.title ?? "Build")
      .task(id: buildID) {
        do {
          try await $build.task(AppBuilderV3Build.byID(buildID))
        } catch is CancellationError {
        } catch {
        }
      }
    }
  }
#endif
