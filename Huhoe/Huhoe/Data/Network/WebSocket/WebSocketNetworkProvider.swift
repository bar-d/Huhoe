//
//  WebSocketNetworkProvider.swift
//  Huhoe
//
//  Created by 임지성 on 2022/04/25.
//

import Foundation

final class WebSocketNetworkProvider {
    private let apiEndPoint: String
    
    init() {
        self.apiEndPoint = "wss://pubwss.bithumb.com/pub/ws"
    }
    
    func makeTransactionWebSocketNetwork(coinSymbols: [String]) -> TransactionWebSocketNetwork {
        let network = WebSocketNetwork(endPoint: apiEndPoint)
        return TransactionWebSocketNetwork(network: network)
    }
}
