#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <readpassphrase.h>
#include <unistd.h>

#ifndef UGREEN_KEYCHAIN_SERVICE
#define UGREEN_KEYCHAIN_SERVICE "io.github.ugreen-nas-mcp-macos"
#endif
#ifndef UGREEN_LEGACY_KEYCHAIN_SERVICE
#define UGREEN_LEGACY_KEYCHAIN_SERVICE "io.local.codex.ugreen-nas"
#endif

static int fail(const char *message, OSStatus status) {
    fprintf(stderr, "UGREEN Keychain: %s", message);
    if (status != errSecSuccess) fprintf(stderr, " (OSStatus %d)", (int)status);
    fputc('\n', stderr);
    return 1;
}

static NSDictionary *itemQuery(NSString *service) {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: @"unc-open-platform",
    };
}

static NSDictionary *decodeJSON(NSData *data) {
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSDictionary *credential(id token, id address) {
    if (![token isKindOfClass:[NSString class]] || ![address isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSRange match = [token rangeOfString:@"^ugpoa_v1\\.[A-Za-z0-9_.-]+$"
                                options:NSRegularExpressionSearch];
    if (match.location != 0 || match.length != [token length]) return nil;

    NSURLComponents *url = [NSURLComponents componentsWithString:address];
    NSString *host = url.host.lowercaseString;
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || !host.length ||
        url.user || url.password || url.query || url.fragment ||
        (url.path.length && ![url.path isEqualToString:@"/"]) ||
        (url.port && (url.port.integerValue < 1 || url.port.integerValue > 65535)) ||
        [host isEqualToString:@"ug.link"] || [host isEqualToString:@"www.ug.link"]) return nil;
    return @{@"token": token, @"server_url": address};
}

static NSDictionary *loadCredential(NSString *service, OSStatus *status) {
    NSMutableDictionary *query = [itemQuery(service) mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL;
    *status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (*status != errSecSuccess) return nil;
    NSDictionary *stored = decodeJSON(CFBridgingRelease(result));
    return credential(stored[@"token"], stored[@"server_url"]);
}

static int writeCredential(NSDictionary *record) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:NULL];
    if (!data) return fail("could not encode the credential", 0);
    NSDictionary *query = itemQuery(@UGREEN_KEYCHAIN_SERVICE);
    NSMutableDictionary *item = [query mutableCopy];
    item[(__bridge id)kSecAttrLabel] = @"UGREEN NAS MCP (macOS)";
    item[(__bridge id)kSecValueData] = data;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status == errSecDuplicateItem) {
        NSDictionary *updates = @{(__bridge id)kSecValueData: data};
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)updates);
    }
    if (status != errSecSuccess) return fail("could not save the Keychain item", status);
    puts("UGREEN NAS credential saved to the macOS Keychain.");
    return 0;
}

static NSString *readField(const char *prompt, int flags) {
    char input[4096];
    NSString *value = nil;
    if (readpassphrase(prompt, input, sizeof input, RPP_REQUIRE_TTY | flags)) {
        value = [NSString stringWithUTF8String:input];
    }
    memset_s(input, sizeof input, 0, sizeof input);
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL connected(NSString *binary, NSDictionary *record) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:binary];
    task.arguments = @[@"--format", @"json", @"--timeout", @"15", @"auth", @"status", @"--check"];
    NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    env[@"UNC_NAS_TOKEN"] = record[@"token"];
    env[@"UNC_NAS_URL"] = record[@"server_url"];
    task.environment = env;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    if (![task launchAndReturnError:NULL]) return NO;
    NSDictionary *status = decodeJSON([output.fileHandleForReading readDataToEndOfFile]);
    [task waitUntilExit];
    NSDictionary *opencli = status[@"opencli"];
    return task.terminationStatus == 0 && [status[@"authenticated"] isEqual:@YES] &&
        [opencli isKindOfClass:[NSDictionary class]] && [opencli[@"connected"] isEqual:@YES];
}

static BOOL allowedInvocation(int argc, char **argv) {
    if (argc < 6 || strcmp(argv[1], "--format") || strcmp(argv[3], "--timeout") ||
        (strcmp(argv[2], "json") && strcmp(argv[2], "raw")) || strcmp(argv[4], "30")) return NO;
    NSString *command = @(argv[5]);
    if ([command isEqualToString:@"auth"]) {
        return argc >= 7 && !strcmp(argv[6], "status") &&
            (argc == 7 || (argc == 8 && !strcmp(argv[7], "--check")));
    }
    NSArray *commands = @[@"app", @"ctl", @"docker", @"download", @"file", @"network",
                          @"search", @"storage", @"taskmgr", @"doctor"];
    NSArray *blocked = @[@"--token", @"--server-url", @"--client-id", @"--client-secret",
                         @"--debug", @"--verbose", @"-v", @"--insecure"];
    if (![commands containsObject:command]) return NO;
    for (int i = 6; i < argc; i++) {
        NSString *flag = [@(argv[i]) componentsSeparatedByString:@"="].firstObject;
        if ([blocked containsObject:flag]) return NO;
    }
    return YES;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        unsetenv("UNC_NAS_TOKEN");
        unsetenv("UNC_NAS_URL");
        unsetenv("UNC_NAS_INSECURE");

        const char *configured = getenv("UGREEN_KEYCHAIN_UNC_BIN");
        NSString *binary = configured ? [NSString stringWithUTF8String:configured] :
            [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin/unc"];
        NSString *resolved = binary.stringByResolvingSymlinksInPath;
        if (!binary.isAbsolutePath || ![[NSFileManager defaultManager] isExecutableFileAtPath:binary] ||
            [resolved isEqualToString:[@(argv[0]) stringByResolvingSymlinksInPath]]) {
            return fail("set UGREEN_KEYCHAIN_UNC_BIN to an absolute path to the official unc", 0);
        }

        NSDictionary *record = nil;
        BOOL save = NO;
        OSStatus status = errSecSuccess;
        if (argc == 2 && !strcmp(argv[1], "--store")) {
            save = YES;
            NSString *address = readField("NAS HTTPS URL: ", RPP_ECHO_ON);
            if (!address.length) return fail("provide a NAS HTTPS URL in a local terminal", 0);
            NSString *token = readField("NAS access token: ", RPP_ECHO_OFF);
            record = credential(token, address);
        } else if ((argc == 2 || argc == 3) && !strcmp(argv[1], "--import-cache")) {
            save = YES;
            NSString *cache = argc == 3 ? @(argv[2]) :
                [NSHomeDirectory() stringByAppendingPathComponent:@".unc/auth.json"];
            NSDictionary *old = decodeJSON([NSData dataWithContentsOfFile:cache]);
            record = credential(old[@"token"], old[@"server_url"]);
        } else if (argc == 2 && !strcmp(argv[1], "--import-legacy-keychain")) {
            save = YES;
            record = loadCredential(@UGREEN_LEGACY_KEYCHAIN_SERVICE, &status);
        }
        if (save) {
            if (!record) return fail("expected a valid Open CLI token and HTTPS NAS origin", status);
            if (!connected(binary, record)) return fail("NAS authentication could not be verified", 0);
            return writeCredential(record);
        }

        BOOL check = argc == 2 && !strcmp(argv[1], "--check");
        if (!check && !allowedInvocation(argc, argv)) return fail("unsupported MCP invocation", 0);
        if (check || strcmp(argv[argc - 1], "--help")) {
            record = loadCredential(@UGREEN_KEYCHAIN_SERVICE, &status);
            if (!record) return fail("could not read the NAS credential from the Keychain", status);
            if (check) {
                if (!connected(binary, record)) return fail("NAS authentication could not be verified", 0);
                puts("Keychain credential and NAS connection verified.");
                return 0;
            }
            if (setenv("UNC_NAS_TOKEN", [record[@"token"] UTF8String], 1) ||
                setenv("UNC_NAS_URL", [record[@"server_url"] UTF8String], 1)) {
                return fail("could not prepare the UNC process environment", 0);
            }
        }
        const char *executable = binary.fileSystemRepresentation;
        argv[0] = (char *)executable;
        execv(executable, argv);
        return fail("could not start the official unc", 0);
    }
}
