import Foundation

enum ScrobblingMethod: String, CaseIterable, Codable, Identifiable {
    case accessibility = "accessibility"
    case logging = "logging"
    case systemNowPlaying = "system_now_playing"
    case ipc = "ipc"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .accessibility:
            return "Accessibility API"
        case .logging:
            return "Чтение логов"
        case .systemNowPlaying:
            return "Системный плеер (Control Center)"
        case .ipc:
            return "IPC Bridge"
        }
    }
    
    var description: String {
        switch self {
        case .accessibility:
            return "Читает метаданные из окна Яндекс Музыки напрямую"
        case .logging:
            return "Парсит файл логов Яндекс Музыки. Файл создается автоматически."
        case .systemNowPlaying:
            return "Использует информацию из системного плеера macOS (Control Center)"
        case .ipc:
            return "Прямой IPC-мост с модифицированной Яндекс Музыкой"
        }
    }
}
