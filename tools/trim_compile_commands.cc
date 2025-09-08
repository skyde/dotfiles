// Minimal streaming filter for compile_commands.json
// Builds a reduced database containing only entries whose "file" path
// matches selected prefixes. Avoids loading entire 52MB JSON in memory.
// Usage (from //src):
//   clang++ -std=c++17 -O2 tools/dev/trim_compile_commands.cc -o out/Default/trim_cc && \
//   ./out/Default/trim_cc compile_commands.json out/Default/compile_commands.trimmed.json cc/ base/ gpu/ ui/
// The prefixes are matched after normalizing leading ../../ in the JSON entry.
// Produces a valid JSON array.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <iostream>

static bool hasPrefix(const std::string& path, const std::string& prefix) {
    if (path.size() < prefix.size()) return false;
    return std::equal(prefix.begin(), prefix.end(), path.begin());
}

int main(int argc, char** argv) {
    if (argc < 4) {
        std::fprintf(stderr, "Usage: %s <input compile_commands.json> <output> <prefix1> [prefix2 ...]\n", argv[0]);
        return 1;
    }
    const char* inPath = argv[1];
    const char* outPath = argv[2];
    std::vector<std::string> prefixes;
    for (int i=3;i<argc;i++) {
        std::string p = argv[i];
        if (p.rfind("../../",0)==0) p = p.substr(6); // normalize possible leading ../../
        if (p.size() && p.back()=='/') p.pop_back();
        prefixes.push_back(p);
    }

    std::ifstream in(inPath);
    if (!in) { std::perror(inPath); return 2; }
    std::ofstream out(outPath);
    if (!out) { std::perror(outPath); return 3; }

    // We'll do a naive streaming parse: scan for '{', then accumulate until matching '}', tracking braces.
    // Inside each object, capture the substring for key "file": "...".
    out << "[\n";
    bool first=true;
    char c;
    while (in.get(c)) {
        if (c=='{') {
            std::string obj; obj.push_back(c);
            int depth=1; bool inString=false; bool escape=false;
            while (depth>0 && in.get(c)) {
                obj.push_back(c);
                if (escape) { escape=false; continue; }
                if (c=='\\') { escape=true; continue; }
                if (c=='"') inString=!inString;
                if (!inString) {
                    if (c=='{') depth++;
                    else if (c=='}') depth--;
                }
            }
            // Extract file field.
            std::string filePath;
            std::string key = "\"file\"";
            size_t pos = obj.find(key);
            if (pos!=std::string::npos) {
                pos = obj.find('"', pos + key.size());
                if (pos!=std::string::npos) {
                    size_t end = obj.find('"', pos+1);
                    if (end!=std::string::npos) {
                        filePath = obj.substr(pos+1, end-pos-1);
                        // Normalize leading ../../
                        if (filePath.rfind("../../",0)==0) filePath = filePath.substr(6);
                    }
                }
            }
            bool keep=false;
            for (auto& p: prefixes) {
                if (hasPrefix(filePath, p)) { keep=true; break; }
            }
            if (keep) {
                if (!first) out << ",\n"; else first=false;
                out << obj;
            }
        }
    }
    out << "\n]\n";
    out.close();
    std::cerr << "Trimmed compile_commands written to " << outPath << "\n";
    return 0;
}
