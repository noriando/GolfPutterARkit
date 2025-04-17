//
//  ChatGPTService.swift
//  GolfPutterARkit
//
//  Created by Norihisa Ando on 2025/04/05.
//
// ChatGPTService.swift
import Foundation
import UIKit

class ChatGPTService {
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func getPuttingAdvice(puttData: String, image: UIImage?, completion: @escaping (String?, Error?) -> Void) {
        print("LOG: Starting ChatGPT API request")
        let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        let image = image
        let imageData = image?.jpegData(compressionQuality: 0.7)
            // With image
        let base64Image = imageData!.base64EncodedString()

        let prompt = """
        あなたはプロのゴルフパッティングコーチです。以下のパットラインのサマリー情報が提供されています:

        \(puttData)

        以下の項目を必ず含めた、明確で論理的なパッティングアドバイスを提供してください:

        1. ラインの全長（合計距離）を必ず記載。
        2. 傾斜変化ポイント（上り→下り、下り→上り、左右の変化）がある場合は、必ず何cm地点かを明記。
        3. 『フック（左に曲がる）』の場合は『ホールの右』を狙う。『スライス（右に曲がる）』の場合は『ホールの左』を狙うこと。
        4. 狙う位置を必ず「ホールの左右±〇〇cm」と数値で記載すること（真っ直ぐの場合は±0cm）。
        5. 打つ強さを必ず具体的に指示（通常の何%の強さか）。

        【注意事項】
        - 曖昧な表現は禁止（「やや」「少し」等）。
        - ブレークの方向と狙い位置の指示を間違えないこと。
        - 左右傾斜が±0.3°以内の場合は、ラインはほぼ真っ直ぐであると判断し、「ホールの中心（±0cm）を狙う」と指示すること。
        """

        // Prepare request body
        let requestBody: [String: Any] = [
            "model": "gpt-4o-2024-08-06",
            "messages": [
                ["role": "system", "content": "あなたはプロのゴルフパッティングコーチです。簡潔な日本語のアドバイスを提供します。"],
                ["role": "user", "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                ]]
            ],
            "max_tokens": 1000
        ]

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        print("LOG: Sending request to ChatGPT API...")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            print("LOG: Received \(data?.count ?? 0) bytes of data")
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                completion(content, nil)
                // This is the actual advice text from ChatGPT - print it clearly
                print("LOG: ChatGPT ADVICE: \(content)")
             
            } else {
                print("LOG: ERROR - Could not parse choices from response")
                completion(nil, NSError(domain: "ChatGPTService", code: 1, userInfo: [NSLocalizedDescriptionKey: "データ解析エラー"]))
            }
        }.resume()
    }
}
