//
//  FeedbackFormView.swift
//  HapticVideoApp
//
//  In-app feedback form that submits directly as a GitHub Issue
//

import SwiftUI

struct FeedbackFormView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @State private var satisfaction: Int = 5
    @State private var hapticPreference: String = "Balanced"
    @State private var textFeedback: String = ""
    @State private var featureRequest: String = ""
    
    let hapticOptions = ["Subtle", "Balanced", "Intense"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("App Experience")) {
                    VStack(alignment: .leading) {
                        Text("Overall Satisfaction: \(satisfaction)/10")
                        Slider(value: Binding(get: {
                            Double(self.satisfaction)
                        }, set: { newValue in
                            self.satisfaction = Int(newValue)
                        }), in: 1...10, step: 1)
                    }
                    
                    Picker("Haptic Preference", selection: $hapticPreference) {
                        ForEach(hapticOptions, id: \.self) {
                            Text($0)
                        }
                    }
                }
                
                Section(header: Text("Details")) {
                    TextField("Any bugs or issues?", text: $textFeedback, axis: .vertical)
                        .lineLimit(3...6)
                    
                    TextField("Any feature requests?", text: $featureRequest, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Button(action: submitFeedback) {
                        HStack {
                            Spacer()
                            Text("Submit as GitHub Issue")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(AppColors.primary)
                }
            }
            .navigationTitle("Give Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func submitFeedback() {
        let title = "User Feedback: \(satisfaction)/10 Satisfaction"
        
        let body = """
        ## App Experience
        **Satisfaction:** \(satisfaction)/10
        **Haptic Preference:** \(hapticPreference)
        
        ## Feedback / Issues
        \(textFeedback.isEmpty ? "None" : textFeedback)
        
        ## Feature Requests
        \(featureRequest.isEmpty ? "None" : featureRequest)
        """
        
        let urlString = "https://github.com/banthia14aman/HapticVideoApp/issues/new?title=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
            presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    FeedbackFormView()
}
