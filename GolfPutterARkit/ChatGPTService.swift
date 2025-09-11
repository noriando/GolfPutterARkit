// ChatGPTService.swift
import Foundation
import UIKit
import AVFoundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ChatGPTService")

class ChatGPTService {
    private let apiKey: String
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var voiceEnabled: Bool = true
    
    init(apiKey: String, voiceEnabled: Bool = true) {
        self.apiKey = apiKey
        self.voiceEnabled = voiceEnabled
    }
   
    func toggleVoice() -> Bool {
        voiceEnabled.toggle()
        if !voiceEnabled && speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        return voiceEnabled
    }

    
    func getPuttingAdvice(puttData: String, image: UIImage?, completion: @escaping (String?, Error?) -> Void) {
        logger.info("Starting ChatGPT API request")
        let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        let image = image
        let imageData = image?.jpegData(compressionQuality: 0.7)
        let base64Image = imageData!.base64EncodedString()

        let prompt = """
        あなたはプロゴルファーの専属キャディです。以下のパッティング分析と画像を見て、実際のキャディのようにアドバイスしてください：
        ARデータから下記の通りパターを知ればHOLEの入れることができます。下記は、そのシミュレーション情報です。
        下記のシミュレーション情報をキャディの言葉に変換してください。

        \(puttData)

        キャディとしてのアドバイス形式：（番号は言わなくて結構です）
        1. 距離をヤード/フィートで表現
        2. 傾斜状況を説明（「少し上り」「結構な下り」など）
        3. ブレークがあれば方向と程度（「カップ1個分右」「2個分左」など）
        4. 狙い位置を具体的に（「カップの右エッジ」「カップ2個分右」など）
        5. 打つ強さを距離で表現（「3ヤードで打つ」「5ヤード強で」など）
        6. 画像から見える特徴があれば参考に（「あの木の方向」「右の砂場の手前」など）。なければ画像については無視してください。

        パワー変換：
        - 0.8 = 実距離より軽く（下り坂）
        - 1.0 = 距離通り（平坦）
        - 1.3 = 少し強め（軽い上り）
        - 1.5+ = しっかり強め（きつい上り）

        例：「2ヤードの距離、少し上りなので3ヤードの気持ちで、カップの右エッジを狙って打ってください」

        実際のキャディのように、親しみやすく、自信を持って、具体的にアドバイスしてください。
        """
        
        
        logger.info("ChatGPT prompt: \(prompt)")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "あなたはプロのゴルフパッティングコーチです。簡潔で実践的な日本語のアドバイスを提供します。"],
                ["role": "user", "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                ]]
            ],
            "max_tokens": 500
        ]

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        logger.info("Sending request to ChatGPT API...")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error = error {
                logger.error("ChatGPT API request failed: \(error)")
                completion(nil, error)
                return
            }
            
            logger.debug("Received \(data?.count ?? 0) bytes of data")
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                
                logger.info("ChatGPT ADVICE: \(content)")
                completion(content, nil)
                
                // Speak the advice using voice synthesis
                DispatchQueue.main.async {
                    self?.speakAdvice(content)
                }
                
            } else {
                logger.error("ERROR - Could not parse choices from response")
                completion(nil, NSError(domain: "ChatGPTService", code: 1, userInfo: [NSLocalizedDescriptionKey: "データ解析エラー"]))
            }
        }.resume()
    }
    
    private func speakAdvice(_ text: String) {
        guard voiceEnabled else { return }
        
        // Stop any current speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Clean up the text for better speech
        let cleanText = cleanTextForSpeech(text)
        
        let utterance = AVSpeechUtterance(string: cleanText)
        
        // Configure voice for Japanese
        if let japaneseVoice = AVSpeechSynthesisVoice(language: "ja-JP") {
            utterance.voice = japaneseVoice
        }
        
        // Configure speech parameters for natural, faster speech
        utterance.rate = 0.6 // Increased from 0.45 - try values between 0.5-0.7
        utterance.pitchMultiplier = 1.1 // Slightly higher pitch sounds more natural
        utterance.volume = 0.9
        
        // Add pre and post utterance delay for more natural speech
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1
        
        logger.info("Speaking advice: \(cleanText)")
        speechSynthesizer.speak(utterance)
    }
    
    private func cleanTextForSpeech(_ text: String) -> String {
        var cleanText = text
        
        // Remove markdown and formatting
        cleanText = cleanText.replacingOccurrences(of: "###", with: "")
        cleanText = cleanText.replacingOccurrences(of: "**", with: "")
        cleanText = cleanText.replacingOccurrences(of: "*", with: "")
        
        // Convert symbols to spoken Japanese
        cleanText = cleanText.replacingOccurrences(of: "°", with: "度")
        cleanText = cleanText.replacingOccurrences(of: "%", with: "パーセント")
        cleanText = cleanText.replacingOccurrences(of: "±", with: "プラスマイナス")
        cleanText = cleanText.replacingOccurrences(of: "cm", with: "センチメートル")
        cleanText = cleanText.replacingOccurrences(of: "mm", with: "ミリメートル")
        
        // Remove excessive whitespace and line breaks for speech
        cleanText = cleanText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return cleanText
    }
    
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
}
