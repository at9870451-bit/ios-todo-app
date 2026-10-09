import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @State private var input: String = ""
    @State private var editing: Todo?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProgressCard()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    ForEach(store.todos) { todo in
                        TodoRow(todo: todo) {
                            store.toggle(todo)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(todo)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                editing = todo
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                    }
                } header: {
                    if !store.todos.isEmpty {
                        HStack {
                            Text("待办")
                            Spacer()
                            if store.doneCount > 0 {
                                Button("清除已完成") { store.clearDone() }
                                    .font(.caption)
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的清单")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                InputBar(text: $input, focused: $inputFocused) {
                    store.add(input)
                    input = ""
                    inputFocused = true
                }
            }
            .overlay {
                if store.todos.isEmpty {
                    ContentUnavailableView(
                        "还没有待办",
                        systemImage: "checklist",
                        description: Text("在下面输入框里加一条吧")
                    )
                }
            }
            .sheet(item: $editing) { todo in
                RenameSheet(todo: todo) { title in
                    store.rename(todo, to: title)
                    editing = nil
                } onCancel: {
                    editing = nil
                }
                .presentationDetents([.height(200)])
            }
            .animation(.snappy, value: store.todos)
        }
    }
}

// MARK: - 顶部进度卡

private struct ProgressCard: View {
    @EnvironmentObject private var store: TodoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("完成进度")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(store.doneCount) / \(store.todos.count)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("今日新增")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(store.todayCount)")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.blue)
                        .contentTransition(.numericText())
                }
            }

            ProgressView(value: store.progress)
                .tint(.blue)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            if store.todos.isEmpty == false && store.progress >= 1 {
                Label("全部完成，厉害！", systemImage: "party.popper.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - 单行

private struct TodoRow: View {
    let todo: Todo
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? .blue : .secondary)
                    .symbolEffect(.bounce, value: todo.isDone)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .strikethrough(todo.isDone, color: .secondary)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)

                Text(todo.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - 底部输入条

private struct InputBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("添加待办…", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))

            Button(action: onSubmit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(
                            text.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(Color.secondary.opacity(0.35))
                            : AnyShapeStyle(Color.blue)
                        )
                    )
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            .animation(.snappy, value: text.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - 重命名面板

private struct RenameSheet: View {
    let todo: Todo
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var value: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $value)
                    .focused($focused)
                    .onSubmit { onSave(value) }
            }
            .navigationTitle("重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(value) }
                        .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                value = todo.title
                // 延迟一帧再聚焦，否则 sheet 动画会把键盘顶掉
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focused = true
                }
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(TodoStore())
}
