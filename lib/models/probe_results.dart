typedef UrlTestResult = ({
  bool success,
  int? latencyMs,
  String error,
  int? httpStatus,
});

typedef ServerUrlTestResult = ({
  String id,
  bool success,
  int? latencyMs,
  String error,
  int? httpStatus,
});

typedef SpeedTestResult = ({bool success, int? kbps, String error});

typedef ServerSpeedTestResult = ({
  String id,
  bool success,
  int? kbps,
  String error,
});

typedef ServerLatency = ({String id, bool success, int? latencyMs});
