import AuditorPolicy
import SwiftUI

struct PolicyPicker: View {
    @Binding var selectedPolicyID: String?
    let policies: [Policy]
    var includeNone: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(policies) { policy in
                policyRow(
                    id: policy.id,
                    title: policy.displayName,
                    subtitle: policySubtitle(policy)
                )
            }
            if includeNone {
                policyRow(
                    id: nil,
                    title: "Universal rules only",
                    subtitle: "Filename lint without a naming template or taxonomy."
                )
            }
        }
    }

    private func policySubtitle(_ policy: Policy) -> String {
        var parts: [String] = []
        if let template = policy.namingTemplate {
            parts.append("Template: \(template)")
        }
        if !policy.folderTaxonomy.isEmpty {
            parts.append("\(policy.folderTaxonomy.count) suggested folders")
        }
        parts.append("\(policy.expirationHorizonDays)-day expiration horizon")
        return parts.joined(separator: " · ")
    }

    private func policyRow(id: String?, title: String, subtitle: String) -> some View {
        let selected = selectedPolicyID == id
        return Button {
            selectedPolicyID = id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
