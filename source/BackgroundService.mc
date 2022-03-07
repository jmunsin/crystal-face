using Toybox.Background as Bg;
using Toybox.System as Sys;
using Toybox.Communications as Comms;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Time.Gregorian;

(:background)
class BackgroundService extends Sys.ServiceDelegate {
	var minHr = null;
	
	(:background_method)
	function initialize() {
		Sys.ServiceDelegate.initialize();
	}

	// Read pending web requests, and call appropriate web request function.
	// This function determines priority of web requests, if multiple are pending.
	// Pending web request flag will be cleared only once the background data has been successfully received.
	(:background_method)
	function onTemporalEvent() {
		//Sys.println("onTemporalEvent");
		// Register for background temporal event as soon as possible.
		var lastTime = Bg.getLastTemporalEventTime();
		if (lastTime) {
			// Events scheduled for a time in the past trigger immediately.
			var nextTime = lastTime.add(new Time.Duration(5 * 60));
			Bg.registerForTemporalEvent(nextTime);
		} else {
			Bg.registerForTemporalEvent(Time.now());
		}
		var min = ActivityMonitor.getHeartRateHistory(new Time.Duration(300), true).getMax();
		if (min == null || min == 255) {
			min = ActivityMonitor.getHeartRateHistory(new Time.Duration(14400), true).getMin();
		}
		if (minHr == null || min < minHr) {
			minHr = min;
		}
		var propMinHr = App.getApp().getProperty("MinHr");
		var sendHr = false;
		if (propMinHr == null) {
			sendHr = true;
		} else if (minHr < propMinHr) {
			sendHr = true;
		} else {
			var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
			var lastDay = App.getApp().getProperty("LastHrPollDay");
			if (lastDay != now.day) {
				sendHr = true;
			}
		}
		//Sys.println("rhhr: " + minHr);
		var pendingWebRequests = App.getApp().getProperty("PendingWebRequests");
		if (pendingWebRequests != null) {

			// 1. City local time.
			if (pendingWebRequests["CityLocalTime"] != null) {
				makeWebRequest(
					"https://script.google.com/macros/s/AKfycbwPas8x0JMVWRhLaraJSJUcTkdznRifXPDovVZh8mviaf8cTw/exec",
					{
						"city" => App.getApp().getProperty("LocalTimeInCity")
					},
					method(:onReceiveCityLocalTime)
				);

			// 2. Weather.
			} else if (pendingWebRequests["OpenWeatherMapCurrent"] != null) {
				var owmKeyOverride = App.getApp().getProperty("OWMKeyOverride");
				makeWebRequest(
					"https://api.openweathermap.org/data/2.5/weather",
					{
						"lat" => App.getApp().getProperty("LastLocationLat"),
						"lon" => App.getApp().getProperty("LastLocationLng"),

						// Polite request from Vince, developer of the Crystal Watch Face:
						//
						// Please do not abuse this API key, or else I will be forced to make thousands of users of Crystal
						// sign up for their own Open Weather Map free account, and enter their key in settings - a much worse
						// user experience for everyone.
						//
						// Crystal has been registered with OWM on the Open Source Plan, which lifts usage limits for free, so
						// that everyone benefits. However, these lifted limits only apply to the Current Weather API, and *not*
						// the One Call API. Usage of this key for the One Call API risks blocking the key for everyone.
						//
						// If you intend to use this key in your own app, especially for the One Call API, please create your own
						// OWM account, and own key. You should be able to apply for the Open Source Plan to benefit from the same
						// lifted limits as Crystal. Thank you.
						"appid" => ((owmKeyOverride != null) && (owmKeyOverride.length() == 0)) ? "2651f49cb20de925fc57590709b86ce6" : owmKeyOverride,

						"units" => "metric" // Celcius.
					},
					method(:onReceiveOpenWeatherMapCurrent)
				);
			} else {
				if (sendHr) {
					Bg.exit({
						"MinHr" => minHr
					});
				}
			}
		} else {
			if (sendHr) {
				Bg.exit({
					"MinHr" => minHr
				});
			}
		}
	}

	// Sample time zone data:
	/*
	{
	"requestCity":"london",
	"city":"London",
	"current":{
		"gmtOffset":3600,
		"dst":true
		},
	"next":{
		"when":1540688400,
		"gmtOffset":0,
		"dst":false
		}
	}
	*/

	// Sample error when city is not found:
	/*
	{
	"requestCity":"atlantis",
	"error":{
		"code":2, // CITY_NOT_FOUND
		"message":"City \"atlantis\" not found."
		}
	}
	*/
	(:background_method)
	function onReceiveCityLocalTime(responseCode, data) {

		// HTTP failure: return responseCode.
		// Otherwise, return data response.
		if (responseCode != 200) {
			data = {
				"httpError" => responseCode
			};
		}

		Bg.exit({
			"CityLocalTime" => data,
			"MinHr" => minHr
		});
	}

	// Sample invalid API key:
	/*
	{
		"cod":401,
		"message": "Invalid API key. Please see http://openweathermap.org/faq#error401 for more info."
	}
	*/

	// Sample current weather:
	/*
	{
		"coord":{
			"lon":-0.46,
			"lat":51.75
		},
		"weather":[
			{
				"id":521,
				"main":"Rain",
				"description":"shower rain",
				"icon":"09d"
			}
		],
		"base":"stations",
		"main":{
			"temp":281.82,
			"pressure":1018,
			"humidity":70,
			"temp_min":280.15,
			"temp_max":283.15
		},
		"visibility":10000,
		"wind":{
			"speed":6.2,
			"deg":10
		},
		"clouds":{
			"all":0
		},
		"dt":1540741800,
		"sys":{
			"type":1,
			"id":5078,
			"message":0.0036,
			"country":"GB",
			"sunrise":1540709390,
			"sunset":1540744829
		},
		"id":2647138,
		"name":"Hemel Hempstead",
		"cod":200
	}
	*/
	(:background_method)
	function onReceiveOpenWeatherMapCurrent(responseCode, data) {
		var result;
		
		// Useful data only available if result was successful.
		// Filter and flatten data response for data that we actually need.
		// Reduces runtime memory spike in main app.
		if (responseCode == 200) {
			result = {
				"cod" => data["cod"],
				"lat" => data["coord"]["lat"],
				"lon" => data["coord"]["lon"],
				"dt" => data["dt"],
				"temp" => data["main"]["temp"],
				"humidity" => data["main"]["humidity"],
				"icon" => data["weather"][0]["icon"]
			};

		// HTTP error: do not save.
		} else {
			result = {
				"httpError" => responseCode
			};
		}

		Bg.exit({
			"OpenWeatherMapCurrent" => result,
			"MinHr" => minHr
		});
	}

	(:background_method)
	function makeWebRequest(url, params, callback) {
		var options = {
			:method => Comms.HTTP_REQUEST_METHOD_GET,
			:headers => {
					"Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED},
			:responseType => Comms.HTTP_RESPONSE_CONTENT_TYPE_JSON
		};

		Comms.makeWebRequest(url, params, options, callback);
	}
}
