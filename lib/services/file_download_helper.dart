// BU Gate2Eat — File Download Helper Conditional Export
export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';
