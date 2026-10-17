import Foundation
import SQLite3

@main
struct IMDbPeopleNavigationTests {
    @MainActor
    static func main() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Denbox-people-\(UUID().uuidString).sqlite")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw IMDbPeopleNavigationTestFailure(message: "could not create the people fixture database")
        }
        defer {
            sqlite3_close(database)
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
        }

        let fixture = """
        CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        INSERT INTO metadata(key,value) VALUES('people_ready','1');
        CREATE TABLE people(
          nconst TEXT PRIMARY KEY,primary_name TEXT NOT NULL,birth_year INTEGER,death_year INTEGER,
          primary_profession TEXT NOT NULL,known_for_titles TEXT NOT NULL
        );
        CREATE TABLE title_principals(
          tconst TEXT NOT NULL,nconst TEXT NOT NULL,category TEXT NOT NULL,job TEXT,characters TEXT,ordering INTEGER NOT NULL,
          PRIMARY KEY(tconst,nconst,category,ordering)
        );
        INSERT INTO people VALUES('nm0000001','Actor First',1970,NULL,'actor,producer','tt0000001');
        INSERT INTO people VALUES('nm0000002','Actor Second',1980,NULL,'actress','tt0000001');
        INSERT INTO people VALUES('nm0000003','Director Only',1960,NULL,'director','tt0000001');
        INSERT INTO title_principals VALUES('tt0000001','nm0000001','actor',NULL,'Lead',1);
        INSERT INTO title_principals VALUES('tt0000001','nm0000002','actress',NULL,'Co-lead',2);
        INSERT INTO title_principals VALUES('tt0000001','nm0000003','director','director',NULL,3);
        """
        guard sqlite3_exec(database, fixture, nil, nil, nil) == SQLITE_OK else {
            throw IMDbPeopleNavigationTestFailure(message: "could not initialize the people fixture database")
        }

        let store = IMDbMetadataStore.testingStore(databaseURL: databaseURL)
        let people = store.principalPeople(for: "tt0000001")
        try require(people.map(\.nconst) == ["nm0000001", "nm0000002"],
                    "title cast did not preserve IMDb person IDs and principal order")
        try require(people.first?.birthYear == 1970 && people.first?.professions == ["actor", "producer"],
                    "person details were not read from the local IMDb index")
        try require(store.person(for: "nm0000002")?.name == "Actor Second",
                    "a cast person could not be opened by IMDb person ID")
        try require(store.principalPeople(for: "not-an-imdb-id").isEmpty,
                    "invalid IMDb title ID was accepted")

        try require(IMDbGenreLocalization.persianName(for: "Adult") == "بزرگسالان"
                    && IMDbGenreLocalization.persianName(for: "Short") == "کوتاه",
                    "IMDb's official genres are missing Persian labels")
        let modelDatabaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Denbox-genre-browse-\(UUID().uuidString).sqlite")
        let model = LibraryModel(loadRemoteCatalog: false, databaseURL: modelDatabaseURL)
        let portraitURL = URL(string: "https://static.tvmaze.com/actors/1001.jpg")!
        model.openIMDbPerson(named: "  Actor First  ", imdbID: " NM0000001 ", imageURL: portraitURL)
        let idRequest = model.consumePendingIMDbPersonRequest()
        try require(idRequest?.nconst == "nm0000001" && idRequest?.name == "Actor First"
                    && idRequest?.imageURL == portraitURL && model.section == .imdbPeople,
                    "a cast card did not open IMDb People with its normalized IMDb ID and portrait")
        model.openIMDbPerson(named: "Fallback Actor", imdbID: "not-an-imdb-id")
        let nameRequest = model.consumePendingIMDbPersonRequest()
        try require(nameRequest?.nconst == nil && nameRequest?.name == "Fallback Actor",
                    "a cast card with an invalid IMDb ID did not fall back to its name")

        model.browseGenre("Comedy", kind: "Series")
        try require(model.section == .shows && model.selectedGenreFilters == ["Comedy"],
                    "browsing a series genre did not open a filtered series catalog")
        model.browseGenre("Drama", kind: "Movie")
        try require(model.section == .movies && model.selectedGenreFilters == ["Drama"],
                    "browsing a movie genre did not open a filtered movie catalog")

        print("PASS IMDb people/genre navigation: cast-ID routing, portraits, name fallback, person lookup, Persian genres, and browsing")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw IMDbPeopleNavigationTestFailure(message: message) }
    }
}

private struct IMDbPeopleNavigationTestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
