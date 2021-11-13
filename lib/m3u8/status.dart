enum DownloaderStatus {
  Init,
  Preparing,
  Parsing,
  Downloading,
  Merging,
  Converting,
  Cleaning,
  Success,
  ParseFail,
  DownloadFail,
  MergeFail,
  ConvertFail,
  CleanFail,
  Fail,
  Interrupted,
}

bool isSuccess(DownloaderStatus status) {
  return status == DownloaderStatus.Success;
}

bool isFail(DownloaderStatus status) {
  return status == DownloaderStatus.ParseFail ||
      status == DownloaderStatus.DownloadFail ||
      status == DownloaderStatus.MergeFail ||
      status == DownloaderStatus.ConvertFail ||
      status == DownloaderStatus.ConvertFail ||
      status == DownloaderStatus.Fail;
}

bool isInterrupt(DownloaderStatus status) {
  return status == DownloaderStatus.Interrupted;
}
