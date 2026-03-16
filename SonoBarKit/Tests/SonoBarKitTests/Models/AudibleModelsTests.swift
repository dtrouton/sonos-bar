import Foundation
import Testing
@testable import SonoBarKit

@Suite("Audible Model Tests")
struct AudibleModelsTests {

    @Test func testAudibleBookParsesFromJSON() throws {
        let json = """
        {
            "asin": "B08DC99YNB",
            "title": "The Unbelievable Truth, Series 6",
            "authors": [{"name": "Jon Naismith"}],
            "narrators": [{"name": "David Mitchell"}],
            "product_images": {"500": "https://m.media-amazon.com/images/I/81WizwJbi1L._SL500_.jpg"},
            "runtime_length_ms": 6720000,
            "purchase_date": "2023-06-15T10:30:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let book = try decoder.decode(AudibleBook.self, from: json)
        #expect(book.asin == "B08DC99YNB")
        #expect(book.id == "B08DC99YNB")
        #expect(book.title == "The Unbelievable Truth, Series 6")
        #expect(book.author == "Jon Naismith")
        #expect(book.narrator == "David Mitchell")
        #expect(book.coverURL == "https://m.media-amazon.com/images/I/81WizwJbi1L._SL500_.jpg")
        #expect(book.durationMs == 6720000)
        #expect(book.purchaseDate != nil)
    }

    @Test func testAudibleBookHandlesMissingOptionals() throws {
        let json = """
        {
            "asin": "B00AAAABBBB",
            "title": "Minimal Book",
            "authors": [{"name": "Some Author"}],
            "runtime_length_ms": 3600000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let book = try decoder.decode(AudibleBook.self, from: json)
        #expect(book.asin == "B00AAAABBBB")
        #expect(book.title == "Minimal Book")
        #expect(book.author == "Some Author")
        #expect(book.narrator == nil)
        #expect(book.coverURL == nil)
        #expect(book.durationMs == 3600000)
        #expect(book.purchaseDate == nil)
    }

    @Test func testAudibleChapterParsesFromJSON() throws {
        let json = """
        {
            "content_metadata": {
                "chapter_info": {
                    "chapters": [
                        {"title": "Opening Credits", "start_offset_ms": 0, "length_ms": 30000},
                        {"title": "Chapter 1", "start_offset_ms": 30000, "length_ms": 1680000}
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AudibleChapterResponse.self, from: json)
        let chapters = response.chapters
        #expect(chapters.count == 2)

        #expect(chapters[0].index == 0)
        #expect(chapters[0].title == "Opening Credits")
        #expect(chapters[0].startOffsetMs == 0)
        #expect(chapters[0].durationMs == 30000)
        #expect(chapters[0].id == 0)

        #expect(chapters[1].index == 1)
        #expect(chapters[1].title == "Chapter 1")
        #expect(chapters[1].startOffsetMs == 30000)
        #expect(chapters[1].durationMs == 1680000)
        #expect(chapters[1].id == 1)
    }

    @Test func testAudibleListeningPositionParsesFromJSON() throws {
        let json = """
        {
            "items": [
                {"asin": "B08DC99YNB", "last_position_ms": 2640000}
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AudibleListeningPositionResponse.self, from: json)
        let positions = response.items
        #expect(positions.count == 1)
        #expect(positions[0].asin == "B08DC99YNB")
        #expect(positions[0].positionMs == 2640000)
    }
}
