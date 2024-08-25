import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart' show ValueNotifier;
import 'package:flutter_hls_parser/flutter_hls_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stronzflix/backend/api/media.dart';
import 'package:stronzflix/backend/downloads/downloader.dart';
import 'package:stronzflix/utils/simple_http.dart' as http;

import 'download_state.dart';

class DownloadOptions {
    final Variant? variant;
    final Rendition? audio;
    final Uri? url;
    final Watchable watchable;

    const DownloadOptions(this.watchable, {this.variant, this.audio, this.url});
}

class DownloadManager {
    const DownloadManager._();

    static Future<Directory> get downloadDirectory async {
        Directory outputDir = await getApplicationDocumentsDirectory();
        return Directory('${outputDir.path}/Stronzflix/downloads/');
    }

    static ValueNotifier<List<DownloadState>> downloads = ValueNotifier([]);

    static void removeDownload(DownloadState download) async {
        downloads.value = downloads.value.where((e) => e != download).toList();
    }

    static Future<bool> _downloadTitleMetadata(Directory outputDirectory, Title title) async{
        File metadataFile = File('${outputDirectory.path}/metadata.json');
        if(metadataFile.existsSync())
            return true;

        File bannerFile = File('${outputDirectory.path}/banner.jpg');
        await bannerFile.writeAsBytes(await http.getRaw(Uri.parse(title.banner)));

        File posterFile = File('${outputDirectory.path}/poster.jpg');
        await posterFile.writeAsBytes(await http.getRaw(Uri.parse(title.metadata.poster)));

        Map<String, dynamic> metadata = {
            "description": title.description,
            "name": title.name,
        };

        metadataFile.writeAsStringSync(jsonEncode(metadata));
        return true;
    }

    static Future<bool> _downloadEpisodeMetadata(Directory outputDirectory, Episode episode) async {
        Series series = episode.season.series;
        if(!await DownloadManager._downloadTitleMetadata(outputDirectory, series))
            return false;

        String coverID = _calcId("${episode.name}-cover");
        File coverFile = File('${outputDirectory.path}/${coverID}.jpg');
        await coverFile.writeAsBytes(await http.getRaw(Uri.parse(episode.cover)));

        File metadataFile = File('${outputDirectory.path}/metadata.json');
        Map<String, dynamic> metadata = jsonDecode(metadataFile.readAsStringSync());
        metadata["seasons"] ??= [];
        if(metadata["seasons"].where((e) => e["name"] == episode.season.name).isEmpty) {
            metadata["seasons"].add({
                "seasonNo": episode.season.seasonNo,
                "name": episode.season.name,
                "episodes": []
            });
        }

        if(metadata["seasons"].firstWhere((e) => e["name"] == episode.season.name)["episodes"].where((e) => e["name"] == episode.name).isEmpty)
            metadata["seasons"].firstWhere((e) => e["name"] == episode.season.name)["episodes"].add(<String, dynamic>{
                "name": episode.name
            });
    
        Map<String, dynamic> episodeObject = metadata["seasons"].firstWhere(
            (e) => e["name"] == episode.season.name
        )["episodes"].firstWhere((e) => e["name"] == episode.name);
        episodeObject["cover"] = coverID;
        episodeObject["url"] = DownloadManager.calcWatchableId(episode);
        episodeObject["episodeNo"] = episode.episodeNo;

        metadataFile.writeAsStringSync(jsonEncode(metadata));
        return true;        
    }

    static Future<bool> _downloadFilmMetadata(Directory outputDirectory, Film film) async {
        if(!await _downloadTitleMetadata(outputDirectory, film))
            return false;

        File metadataFile = File('${outputDirectory.path}/metadata.json');
        Map<String, dynamic> metadata = jsonDecode(metadataFile.readAsStringSync());

        metadata["url"] = DownloadManager.calcWatchableId(film);

        metadataFile.writeAsStringSync(jsonEncode(metadata));
        return true;
    }

    static Future<bool> _downloadMetadata(Directory outputDirectory, Watchable watchable) async {
        if(watchable is Episode)
            return _downloadEpisodeMetadata(outputDirectory, watchable);
        if(watchable is Film)
            return _downloadFilmMetadata(outputDirectory, watchable);
        return false;
    }

    static String _calcId(String str) => md5.convert(utf8.encode(str)).toString();
    static String calcTitleId(Watchable watchable) =>
        watchable is Film ? DownloadManager._calcId(watchable.name) :
        watchable is Episode ? DownloadManager._calcId(watchable.season.series.name) :
        throw Exception("Unknown watchable type");
    static String calcWatchableId(Watchable watchable) => DownloadManager._calcId(watchable.name);

    static String _downloadName(Watchable watchable) =>
        watchable is Film ? watchable.name :
        watchable is Episode ? "${watchable.season.series.name} - ${watchable.name}" :
        throw Exception("Unknown watchable type");

    static Future<void> download(DownloadOptions options) async {
        String titleID = DownloadManager.calcTitleId(options.watchable);
        String watchableID = DownloadManager.calcWatchableId(options.watchable);
        Directory outputDir = Directory('${(await downloadDirectory).path}${titleID}');
        outputDir.createSync(recursive: true);

        if(Directory(outputDir.path).listSync().any((e) => e.path.contains(watchableID)))
            return;

        DownloadState downloadState = DownloadState(DownloadManager._downloadName(options.watchable), options);
        downloads.value.add(downloadState);

        Downloader downloader = options.url == null ? Downloader.hls : Downloader.direct;
        await downloader.download(options, downloadState, outputDir, watchableID);

        if(!downloadState.hasError && !downloadState.isCanceled)
            await DownloadManager._downloadMetadata(outputDir, options.watchable);
        
        downloader.cleanTmpDownload(downloadState);
        if(!downloadState.hasError || downloadState.isCanceled)
            DownloadManager.removeDownload(downloadState);
    }

    static Future<void> _deleteFilm(Film film) async {
        String titleID = DownloadManager.calcTitleId(film);
        Directory directory = Directory('${(await downloadDirectory).path}${titleID}');
        directory.deleteSync(recursive: true);
    }

    static Future<void> _deleteEpisode(Episode episode) async {
        String titleID = DownloadManager.calcTitleId(episode);
        String watchableID = DownloadManager.calcWatchableId(episode);
        Directory directory = Directory('${(await downloadDirectory).path}${titleID}');
        Map<String, dynamic> metadata = jsonDecode(File('${directory.path}/metadata.json').readAsStringSync());
    
        metadata["seasons"].firstWhere((e) => e["name"] == episode.season.name)["episodes"].removeWhere((e) => e["name"] == episode.name);
        if(metadata["seasons"].firstWhere((e) => e["name"] == episode.season.name)["episodes"].isEmpty)
            metadata["seasons"].removeWhere((e) => e["name"] == episode.season.name);
        if(metadata["seasons"].isEmpty)
            directory.deleteSync(recursive: true);
        else {
            File metadataFile = File('${directory.path}/metadata.json');
            metadataFile.writeAsStringSync(jsonEncode(metadata));
            File coverFile = File('${directory.path}/${_calcId("${episode.name}-cover")}.jpg');
            coverFile.deleteSync();
            File episodeFile = File('${directory.path}/${watchableID}.mp4');
            episodeFile.deleteSync();
        }
    }

    static Future<void> deleteSingle(Watchable watchable) async {
        if(watchable is Film)
            return _deleteFilm(watchable);
        if(watchable is Episode)
            return _deleteEpisode(watchable);
        throw Exception("Unknown watchable type");
    }

    static Future<void> delete(Title title) async {
        String titleID = _calcId(title.name);
        Directory directory = Directory('${(await downloadDirectory).path}${titleID}');
        try {
            directory.deleteSync(recursive: true);
        } catch (_) {
            for(FileSystemEntity entity in directory.listSync())
                try {
                    entity.deleteSync();
                } catch (_) {}
        }
    }
}
