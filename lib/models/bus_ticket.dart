class BusTicket {
  final int id;
  final String fromCity;
  final String toCity;
  final String departureDate;
  final String departureTime;
  final String arrivalDate;
  final String arrivalTime;
  final double price;
  final int totalSeats;
  final String? transportCompany;
  final int durationMinutes;
  final String? fromAddress;
  final String? toAddress;
  final List<dynamic>? intermediateStops;
  final String? busType;
  final int? floor1Seats;
  final int? floor2Seats;
  final List<int>? premiumSeats;
  final double? premiumPrice;
  final double? serviceFeePercent;
  final List<int>? bookedSeats;
  final List<dynamic>? photos;
  final String? operatorPhone;
  final String? passengerComments;

  BusTicket({
    required this.id,
    required this.fromCity,
    required this.toCity,
    required this.departureDate,
    required this.departureTime,
    required this.arrivalDate,
    required this.arrivalTime,
    required this.price,
    required this.totalSeats,
    this.transportCompany,
    required this.durationMinutes,
    this.fromAddress,
    this.toAddress,
    this.intermediateStops,
    this.busType,
    this.floor1Seats,
    this.floor2Seats,
    this.premiumSeats,
    this.premiumPrice,
    this.serviceFeePercent,
    this.bookedSeats,
    this.photos,
    this.operatorPhone,
    this.passengerComments,
  });

  factory BusTicket.fromJson(Map<String, dynamic> json) {
    return BusTicket(
      id: json['id'],
      fromCity: json['from_city'],
      toCity: json['to_city'],
      departureDate: json['departure_date'],
      departureTime: json['departure_time'],
      arrivalDate: json['arrival_date'],
      arrivalTime: json['arrival_time'],
      price: (json['price'] as num).toDouble(),
      totalSeats: json['total_seats'],
      transportCompany: json['transport_company'],
      durationMinutes: json['duration_minutes'] ?? 0,
      fromAddress: json['from_address'],
      toAddress: json['to_address'],
      intermediateStops: json['intermediate_stops'],
      busType: json['bus_type'],
      floor1Seats: json['floor1_seats'],
      floor2Seats: json['floor2_seats'],
      premiumSeats: _intList(json['premiumSeats'] ?? json['premium_seats']),
      premiumPrice: (json['premium_price'] as num?)?.toDouble(),
      serviceFeePercent: (json['service_fee_percent'] as num?)?.toDouble(),
      // details: `bookedSeats` (confirmed seats); list: `reserved_seats`
      bookedSeats: _intList(json['bookedSeats'] ?? json['booked_seats'] ?? json['reserved_seats']),
      photos: json['photos'],
      operatorPhone: json['operator_phone'],
      passengerComments: json['passenger_comments'],
    );
  }

  static List<int>? _intList(dynamic v) =>
      (v as List<dynamic>?)?.map((e) => (e as num).toInt()).toList();
}
