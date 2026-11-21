import 'dart:js' as js;
import 'dart:convert';

void initWebSpeech(Function(String, bool) onSpeech, {double durationSeconds = 3.0}) {
  try {
    js.context.callMethod('eval', ["""
      if (!window.kikoSpeechRec) {
        var SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (SpeechRec) {
          window.kikoSpeechRec = new SpeechRec();
          window.kikoSpeechRec.continuous = true;
          window.kikoSpeechRec.interimResults = true;
          window.kikoSpeechRec.lang = 'en-US';
          
          window.kikoSpeechRec.onresult = function(event) {
            if (window.kikoSpeaking) {
              return; // Ignore mic input while agent is speaking out loud!
            }
            var transcript = '';
            var isFinal = false;
            for (var i = event.resultIndex; i < event.results.length; ++i) {
              transcript += event.results[i][0].transcript;
              if (event.results[i].isFinal) {
                isFinal = true;
              }
            }
            if (window.onKikoSpeech && transcript.trim().length > 0) {
              window.onKikoSpeech(transcript, isFinal);
            }
          };

          window.kikoSpeechRec.onerror = function(event) {
            console.log('Speech rec error: ' + event.error);
          };

          window.kikoSpeechRec.onend = function() {
            if (window.kikoMicActive) {
              try { window.kikoSpeechRec.start(); } catch(e){}
            }
          };
        } else {
          console.log('Web Speech API not supported in this browser.');
        }
      }
      window.kikoMicActive = true;
      try { window.kikoSpeechRec.start(); } catch(e){}
    """]);

    js.context['onKikoSpeech'] = (String transcript, bool isFinal) {
      onSpeech(transcript, isFinal);
    };

    print('Web Speech Recognition initialized successfully.');
  } catch (e) {
    print('Failed to initialize Web Speech Recognition: $e');
  }
}

void stopWebSpeech() {
  try {
    js.context.callMethod('eval', ["""
      window.kikoMicActive = false;
      if (window.kikoSpeechRec) {
        try { window.kikoSpeechRec.stop(); } catch(e){}
      }
    """]);
  } catch (e) {
    print('Failed to stop Web Speech Recognition: $e');
  }
}

Future<double> speakTextAloud(String text) async {
  try {
    final cleanText = text.replaceAll('KIKO:', '').trim();
    js.context.callMethod('eval', ["""
      if ('speechSynthesis' in window) {
        window.speechSynthesis.cancel();
        var utter = new SpeechSynthesisUtterance(${jsonEncode(cleanText)});
        utter.rate = 1.0;
        utter.pitch = 1.0;
        var voices = window.speechSynthesis.getVoices();
        if (voices.length > 0) {
          var preferredVoice = voices.find(function(v) { return v.lang.indexOf('en') !== -1; }) || voices[0];
          utter.voice = preferredVoice;
        }
        window.kikoSpeaking = true;
        utter.onend = function() { window.kikoSpeaking = false; };
        utter.onerror = function() { window.kikoSpeaking = false; };
        window.speechSynthesis.speak(utter);
      }
    """]);
  } catch (e) {
    print('Speech synthesis error: $e');
  }
  return text.length / 14.0;
}
