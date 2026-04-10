import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct AssistantPanelView: View {
    @Bindable var model: StudioModel
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                eyebrow: "LLM Console",
                title: "Xiaohongshu MVP",
                subtitle: "先生成图文文案，再把标题、正文和选图提示推给真机上的自动化发布流程。"
            )

            conversationDeck

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorSection
                    imageStrip
                    generatedCopySection
                    publishSection
                }
                .padding(.bottom, 4)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
        .studioPanel()
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importImages(from: urls)
            }
        }
    }

    private var conversationDeck: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.conversation) { message in
                    HStack {
                        if message.role == .assistant {
                            bubble(message, accent: StudioTheme.panelRaised, isLeading: true)
                            Spacer(minLength: 50)
                        } else {
                            Spacer(minLength: 50)
                            bubble(message, accent: StudioTheme.accent.opacity(0.18), isLeading: false)
                        }
                    }
                }
            }
        }
        .frame(height: 240)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.54))
        )
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt")
                .font(.custom("Avenir Next", size: 17))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)

            Text("描述你要发的小红书主题、图片内容和预期风格。MVP 默认只负责文案生成，不会把 Mac 上的图片同步到 iPhone。")
                .font(.custom("Avenir Next", size: 12))
                .foregroundStyle(StudioTheme.secondaryText)

            TextEditor(text: $model.draft.description)
                .font(.custom("Avenir Next", size: 14))
                .frame(minHeight: 120)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(StudioTheme.panelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )

            HStack(spacing: 12) {
                promptField("Tone", text: $model.draft.tone)
                promptField("Audience", text: $model.draft.audience)
            }

            HStack(spacing: 12) {
                Button {
                    isImporting = true
                } label: {
                    Label("Attach Reference Images", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(fill: StudioTheme.panelRaised, foreground: StudioTheme.primaryText))

                Button {
                    Task { await model.generateCopy() }
                } label: {
                    Label(model.isGeneratingCopy ? "Generating…" : "Generate Copy", systemImage: "sparkles.rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(fill: StudioTheme.accent, foreground: StudioTheme.accentForeground, stroke: StudioTheme.accent.opacity(0.18)))
                .disabled(model.isGeneratingCopy)
            }
        }
    }

    private var imageStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reference Images")
                    .font(.custom("Avenir Next", size: 17))
                    .fontWeight(.semibold)
                    .foregroundStyle(StudioTheme.primaryText)
                Spacer()
                Text("\(model.draft.referenceImages.count) attached")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)
            }

            if model.draft.referenceImages.isEmpty {
                Text("可以不传图，只根据描述生成；如果上传参考图，后端会把它们一并送给 OpenAI 作为视觉上下文。")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(StudioTheme.secondaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.draft.referenceImages) { image in
                            VStack(alignment: .leading, spacing: 8) {
                                if let nsImage = NSImage(data: image.data) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 88)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                Text(image.fileName)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(StudioTheme.secondaryText)
                                    .lineLimit(1)

                                Button("Remove") {
                                    model.removeImage(image)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(StudioTheme.danger)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(StudioTheme.panelRaised)
                            )
                        }
                    }
                }
            }
        }
    }

    private var generatedCopySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generated Copy")
                .font(.custom("Avenir Next", size: 17))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)

            promptField("Title", text: $model.draft.title)
            labeledEditor(title: "Body", text: $model.draft.body, minHeight: 150)
            promptField("Hashtags", text: $model.draft.hashtagsText)
            promptField("Image Hint", text: $model.draft.imageSelectionHint)
        }
    }

    private var publishSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delivery")
                .font(.custom("Avenir Next", size: 17))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)

            HStack(spacing: 12) {
                pickerCard(title: "Automation Model") {
                    Picker("Automation Model", selection: $model.draft.automationModel) {
                        ForEach(AutomationModel.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .labelsHidden()
                }

                pickerCard(title: "Publish Mode") {
                    Picker("Publish Mode", selection: $model.draft.publishMode) {
                        ForEach(WorkflowPublishMode.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .labelsHidden()
                }
            }

            Stepper(value: $model.draft.imageCount, in: 1 ... 9) {
                Text("Device image count: \(model.draft.imageCount)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.primaryText)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(StudioTheme.panelRaised)
            )

            if let device = model.selectedDevice {
                Text(device.status == .connected ? "将投递到 \(device.deviceName)。注意：实际发布依赖设备相册内已有图片。" : "当前选中的设备尚未连接，提交按钮会保持禁用。")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(StudioTheme.secondaryText)
            }

            Button {
                Task { await model.submitWorkflow() }
            } label: {
                Label(model.isSubmittingWorkflow ? "Submitting…" : "Send To Device", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(fill: StudioTheme.warmAccent, foreground: StudioTheme.warmForeground, stroke: StudioTheme.warmAccent.opacity(0.18)))
            .disabled(!model.canSubmitWorkflow || model.isSubmittingWorkflow)
        }
    }

    private func bubble(_ message: ConversationMessage, accent: Color, isLeading: Bool) -> some View {
        VStack(alignment: isLeading ? .leading : .trailing, spacing: 8) {
            Text(message.title)
                .font(.custom("Avenir Next", size: 14))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)
            Text(message.body)
                .font(.custom("Avenir Next", size: 12))
                .foregroundStyle(StudioTheme.secondaryText)
            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioTheme.secondaryText.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(accent)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func promptField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.secondaryText)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(StudioTheme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(StudioTheme.panelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
        }
    }

    private func labeledEditor(title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.secondaryText)
            TextEditor(text: text)
                .font(.custom("Avenir Next", size: 14))
                .frame(minHeight: minHeight)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(StudioTheme.panelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
        }
    }

    private func pickerCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.secondaryText)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(StudioTheme.panelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
        }
    }
}
