//
//  WeatherChip.swift
//  PackingHelper
//
//  Created by Todd Louison on 9/16/25.
//

import SwiftUI
import WeatherKit

struct WeatherChip: View {
    @Namespace private var namespace
    
    let weather: CurrentWeather
    
    @State private var isShowingTemperature: Bool = false
    
    var temperature: String {
        return getCurrentWeatherFormattedTemperature(currentTemperature: weather.temperature)
    }
    
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 0) {
                    Image(systemName: weather.symbolName)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 15)
                        .contentShape(Circle())
                        .glassEffect()
                        .glassEffectID("weatherIcon", in: namespace)
                        .glassEffectUnion(id: "weather", namespace: namespace)
                        .onTapGesture {
                            withAnimation {
                                isShowingTemperature.toggle()
                            }
                        }
                    
                    if isShowingTemperature {
                        Text(temperature)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            .contentShape(Circle())
                            .glassEffect()
                            .glassEffectID("weatherTemp", in: namespace)
                            .glassEffectUnion(id: "weather", namespace: namespace)
                        
                        Label("\(weather.uvIndex.value)", systemImage: "sun.max")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            .labelIconToTitleSpacing(4)
                            .contentShape(Circle())
                            .glassEffect()
                            .glassEffectID("weatherUV", in: namespace)
                            .glassEffectUnion(id: "weather", namespace: namespace)
                    }
                }
                .animation(.spring(duration: 0.3), value: isShowingTemperature)
            }
        } else {
            HStack(spacing: 30) {
                Image(systemName: weather.symbolName)
                    .onTapGesture {
                        withAnimation {
                            isShowingTemperature.toggle()
                        }
                    }
                
                if isShowingTemperature {
                    Text(temperature)
                    Label("\(weather.uvIndex.value)", systemImage: "sun.max")
                }
            }
            .roundedBox()
            .animation(.spring(duration: 0.3), value: isShowingTemperature)
        }
    }
}

//#Preview {
//    WeatherChip(weather: Weat)
//}
