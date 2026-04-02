import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root
    
    // Cache directory for favicons
    readonly property string cacheDir: {
        var home = Quickshell.env("HOME") || "/tmp";
        return home + "/.cache/noctalia/plugins/bitwarden-rbw-launcher/favicons";
    }
    
    readonly property string metadataPath: cacheDir + "/metadata.json"
    
    // Queue of pending favicon downloads
    property var downloadQueue: []
    property int activeDownloads: 0
    readonly property int maxConcurrent: 2
    
    // Cache metadata structure: hostname -> { status: "success"|"failed", path: string, timestamp: int, attempts: int }
    property var cacheMetadata: ({})
    
    // Retry failed downloads after 7 days (in milliseconds)
    readonly property int retryFailedAfterMs: 7 * 24 * 60 * 60 * 1000
    
    Component.onCompleted: {
        // Ensure cache directory exists and load existing cache
        createCacheDirProcess.running = true;
    }
    
    Process {
        id: createCacheDirProcess
        running: false
        command: ["mkdir", "-p", cacheDir]
        
        onExited: function(exitCode) {
            if (exitCode === 0) {
                Logger.i("FaviconCache", "Cache directory ready: " + cacheDir);
                // Load metadata from JSON file
                loadMetadataProcess.running = true;
            } else {
                Logger.e("FaviconCache", "Failed to create cache directory");
            }
        }
    }
    
    Process {
        id: loadMetadataProcess
        running: false
        command: ["cat", metadataPath]
        property string output: ""
        
        stdout: StdioCollector {
            onStreamFinished: {
                loadMetadataProcess.output = this.text;
            }
        }
        
        onExited: function(exitCode) {
            if (exitCode === 0 && output) {
                try {
                    cacheMetadata = JSON.parse(output);
                    var successCount = 0;
                    var failedCount = 0;
                    
                    for (var hostname in cacheMetadata) {
                        if (cacheMetadata[hostname].status === "success") {
                            successCount++;
                        } else if (cacheMetadata[hostname].status === "failed") {
                            failedCount++;
                        }
                    }
                    
                    Logger.i("FaviconCache", "Loaded metadata: " + successCount + " cached, " + failedCount + " failed");
                } catch(e) {
                    Logger.w("FaviconCache", "Failed to parse metadata, starting fresh");
                    cacheMetadata = {};
                }
            } else {
                Logger.d("FaviconCache", "No metadata file found, starting fresh");
                cacheMetadata = {};
            }
        }
    }
    
    // Extract hostname from URL
    function getHostname(url) {
        if (!url) return "";
        try {
            var match = url.match(/^(?:https?:\/\/)?(?:[^@\n]+@)?(?:www\.)?([^:\/\n?]+)/im);
            return match ? match[1] : "";
        } catch(e) {
            return "";
        }
    }
    
    // Check if hostname is valid for favicon download
    function isValidHostname(hostname) {
        if (!hostname) return false;
        
        // Skip IPv4 addresses (any IP address format)
        if (/^(?:\d{1,3}\.){3}\d{1,3}$/.test(hostname) || hostname === "localhost") {
            return false;
        }
        
        // Skip android applications (domains starting with com.)
        if (/^com\./.test(hostname)) {
            return false;
        }
        
        // Must have at least one dot to be a valid domain
        if (!hostname.includes('.')) {
            return false;
        }
        
        return true;
    }
    
    // Get cached favicon path or null
    function getCachedFavicon(hostname) {
        if (!hostname) return null;
        
        var metadata = cacheMetadata[hostname];
        if (!metadata) return null;
        
        // If successfully cached, return path
        if (metadata.status === "success" && metadata.path) {
            return metadata.path;
        }
        
        // If failed but retry window has passed, allow retry
        if (metadata.status === "failed") {
            var now = Date.now();
            if (now - metadata.timestamp > retryFailedAfterMs) {
                Logger.d("FaviconCache", "Retry window passed for " + hostname + ", will attempt download");
                return null; // Allow retry
            }
            // Still in cooldown period, don't retry
            return null;
        }
        
        return null;
    }
    
    // Check if we should skip downloading (recently failed)
    function shouldSkipDownload(hostname) {
        var metadata = cacheMetadata[hostname];
        if (!metadata || metadata.status !== "failed") return false;
        
        var now = Date.now();
        return (now - metadata.timestamp) < retryFailedAfterMs;
    }
    
    // Request favicon for a URL (returns cached path if available, null otherwise)
    function requestFavicon(url) {
        var hostname = getHostname(url);
        if (!hostname || !isValidHostname(hostname)) return null;
        
        // Check cache first
        var cached = getCachedFavicon(hostname);
        if (cached) return cached;
        
        // Skip if recently failed
        if (shouldSkipDownload(hostname)) {
            return null;
        }
        
        // Queue for download if not already queued
        var alreadyQueued = downloadQueue.some(function(item) {
            return item.hostname === hostname;
        });
        
        if (!alreadyQueued) {
            var existingMetadata = cacheMetadata[hostname];
            downloadQueue.push({
                hostname: hostname,
                url: url,
                attempts: existingMetadata ? (existingMetadata.attempts || 0) : 0
            });
            processQueue();
        }
        
        return null;
    }
    
    // Process download queue
    function processQueue() {
        while (activeDownloads < maxConcurrent && downloadQueue.length > 0) {
            var item = downloadQueue.shift();
            startDownload(item);
        }
    }
    
    // Start downloading a favicon
    function startDownload(item) {
        activeDownloads++;
        
        // Use Google's favicon service which returns PNG directly
        var downloadUrl = "https://www.google.com/s2/favicons?domain=" + item.hostname + "&sz=128";
        
        var outputPath = cacheDir + "/" + item.hostname + ".png";
        
        Logger.d("FaviconCache", "Downloading favicon for " + item.hostname);
        
        var process = downloadProcessComponent.createObject(root, {
            "hostname": item.hostname,
            "downloadUrl": downloadUrl,
            "outputPath": outputPath,
            "item": item
        });
        
        process.running = true;
    }
    
    Component {
        id: downloadProcessComponent
        
        Process {
            property string hostname: ""
            property string downloadUrl: ""
            property string outputPath: ""
            property var item: null
            
            running: false
            
            // Download PNG directly from Google's favicon service (no conversion needed)
            command: ["sh", "-c", 
                "curl -s -L --max-time 10 --fail -o '" + outputPath + "' '" + downloadUrl.replace(/'/g, "'\\''" ) + "'"
            ]
            
            onExited: function(exitCode) {
                activeDownloads--;
                
                if (exitCode === 0) {
                    // Verify file exists and has content
                    var process = checkFileProcessComponent.createObject(root, {
                        "hostname": hostname,
                        "outputPath": outputPath
                    });
                    process.running = true;
                } else {
                    // Mark as failed with timestamp
                    cacheMetadata[hostname] = {
                        status: "failed",
                        path: null,
                        timestamp: Date.now(),
                        attempts: (item.attempts || 0) + 1
                    };
                    saveMetadata();
                }
                
                processQueue();
                this.destroy();
            }
        }
    }
    
    Component {
        id: checkFileProcessComponent
        
        Process {
            id: checkProc
            property string hostname: ""
            property string outputPath: ""
            property string fileSize: ""
            
            running: false
            command: ["stat", "-c", "%s", outputPath]
            
            stdout: StdioCollector {
                onStreamFinished: {
                    checkProc.fileSize = this.text.trim();
                }
            }
            
            onExited: function(exitCode) {
                if (exitCode === 0 && parseInt(fileSize) > 0) {
                    // Update metadata with success
                    cacheMetadata[hostname] = {
                        status: "success",
                        path: outputPath,
                        timestamp: Date.now(),
                        attempts: 0
                    };
                    saveMetadata();
                    
                    Logger.i("FaviconCache", "✓ " + hostname);
                    root.faviconUpdated(hostname);
                } else {
                    // Mark as failed
                    cacheMetadata[hostname] = {
                        status: "failed",
                        path: null,
                        timestamp: Date.now(),
                        attempts: 1
                    };
                    saveMetadata();
                }
                this.destroy();
            }
        }
    }
    
    // Preload favicons for all entries
    function preloadFavicons(entries) {
        var hostnames = {};
        
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            if (entry.uris && entry.uris.length > 0) {
                var hostname = getHostname(entry.uris[0]);
                if (hostname && !hostnames[hostname]) {
                    hostnames[hostname] = true;
                    requestFavicon(entry.uris[0]);
                }
            }
        }
    }
    
    // Save metadata to JSON file
    function saveMetadata() {
        var json = JSON.stringify(cacheMetadata, null, 2);
        saveMetadataProcess.exec(["sh", "-c", "echo '" + json.replace(/'/g, "'\\''") + "' > '" + metadataPath + "'"]);
    }
    
    Process {
        id: saveMetadataProcess
        running: false
        
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                Logger.w("FaviconCache", "Failed to save metadata");
            }
        }
    }
    
    // Verify all entries have their favicons mapped
    function verifyEntries(entries) {
        var missing = 0;
        var failed = 0;
        var cached = 0;
        
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            if (entry.uris && entry.uris.length > 0) {
                var hostname = getHostname(entry.uris[0]);
                if (hostname && isValidHostname(hostname)) {
                    var metadata = cacheMetadata[hostname];
                    if (!metadata) {
                        missing++;
                    } else if (metadata.status === "failed") {
                        failed++;
                    } else if (metadata.status === "success") {
                        cached++;
                    }
                }
            }
        }
        
        Logger.i("FaviconCache", "Verified: " + cached + " cached, " + failed + " failed, " + missing + " missing");
    }
    
    // Clear all failed entries (allows retry for all)
    function clearFailedEntries() {
        var count = 0;
        for (var hostname in cacheMetadata) {
            if (cacheMetadata[hostname].status === "failed") {
                delete cacheMetadata[hostname];
                count++;
            }
        }
        if (count > 0) {
            saveMetadata();
            Logger.i("FaviconCache", "Cleared " + count + " failed entries");
        }
    }
    
    signal faviconUpdated(string hostname)
}
