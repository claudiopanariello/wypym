// =====================================================================
// Claudio Panariello
//
// PATCH
//
// cla.panariello@gmail.com
//
//////////////////// The patch needs a pseudo UGen that I coded called "AdaptSpecCentroid"
//////////////////// Place it in the Extensions folder that should be at Platform.userExtensionDir
//////////////////// Check that you are connected to the correct IN/OUT devices:
//
// =====================================================================

//ServerOptions.devices;
//Server.default.options.inDevice_("Scarlett 6i6 USB");
//Server.default.options.outDevice_("Scarlett 6i6 USB");

//////////////////// Then recompile SC.
s.options.memSize = 2.pow(19);
s.options.blockSize = 64;
s.waitForBoot({
	(
		SynthDef(\net, {
			arg busIn = 0, gain = 1, lag = 0.5, rq = 0.5, gate = 1, busOut = 0;
			var inMic, input, rms, control, envfolIn, freq, flatness, entropy, chain, adaptCentroid, bandpass, freqShift1, freqShift2, local1, local2, output, envelope, cutoffEnv, grain1, grain2;

			inMic = LeakDC.ar(SoundIn.ar(busIn))*gain.lag3(0.5);
			input = Compander.ar(inMic, inMic); //input mic
			rms = RunningSum.rms(Amplitude.ar(input));
			control = (1-(rms.lag2(lag)));
			envfolIn = Lag.ar(rms, lag);

			chain = FFT(LocalBuf.new(2048, 1), input);
			adaptCentroid = AdaptSpecCentroid.kr(input, chain).expexp(20, 2e4, 20, 2000); //my adaptive spec centroid (it's a pseudo UGen)
			SendReply.kr(Impulse.kr(20), '/centroid', adaptCentroid);

			flatness = SpecFlatness.kr(chain).tanh.lag(1);
			entropy = SpectralEntropy.kr(chain, 2048).tanh.lag3(1);
			//flatness.poll(label: \Flatness);
			//entropy.poll(label: \Entropy);
			SendReply.kr(Impulse.kr(20), '/flatness', flatness);
			SendReply.kr(Impulse.kr(20), '/entropy', entropy);

			bandpass = BPF.ar(BPF.ar(input, adaptCentroid, entropy.lag3(2)), adaptCentroid, entropy.lag3(2));
			freqShift1 = FreqShift.ar(bandpass, flatness.neg.lag3(3));
			freqShift2 = FreqShift.ar(bandpass, flatness.neg.lag3(2.8));

			local1 = LocalIn.ar(1, 0);
			local2 = LocalIn.ar(1, 0);

			local1 = LeakDC.ar(freqShift1);
			local2 = LeakDC.ar(freqShift2);

			local1 = (1-flatness)*freqShift1 + (flatness*DelayC.ar(local1, 5.4, 5.4)) + (0.89*DelayC.ar(local2, 9.8, 9.8));
			local2 = (1-flatness)*freqShift2 + (flatness*DelayC.ar(local2, 3.51, 3.51)) + (0.87*DelayC.ar(local1, 7.6, 7.6));

			grain1 = GrainIn.ar(
				numChannels: 1,
				trigger: Impulse.ar((envfolIn.expexp(0.0001, 1.0, 40, 2.0)+adaptCentroid.expexp(20, 2000, 1.0, 43)).lag3(1)),
				dur: flatness.expexp(0.0001, 1.0, 1.0, 0.005).lag3(1),
				in: local1);
			grain2 = GrainIn.ar(
				numChannels: 1,
				trigger: Dust.ar((envfolIn.expexp(0.0001, 1.0, 40, 2.0)+adaptCentroid.expexp(20, 2000, 2.0, 43)).lag3(1)),
				dur: (1-flatness).expexp(0.0001, 1.0, 1.0, 0.005).lag3(1),
				in: local2);

			LocalOut.ar(local1);
			LocalOut.ar(local2);

			envelope = EnvGen.kr(Env.new([0, 1, 1, 0], [30, 510, 60], curve:4), doneAction:2);
			cutoffEnv = EnvGen.kr(Env.cutoff(2), gate, doneAction: Done.freeSelf);
			output = Limiter.ar(GVerb.ar(BLowShelf.ar(
				SelectX.ar(Line.ar(1.0, 0.0, 360), [Mix.new([local1, local2]), Mix.new([grain1, grain2])])), revtime: XLine.kr(0.5, 20.0, 360))*control, 0.9)*envelope*cutoffEnv;
			Out.ar(busOut, output);
		}).add;
		//
		// Just a synth that I use as a digital timer
		SynthDef(\timer, {
			var minutes, seconds;
			minutes = Sweep.kr(Impulse.kr(0), 60.reciprocal).floor(1);
			seconds = Sweep.kr(Impulse.kr(0)).round(0.01)-(60*minutes);
			SendReply.kr(Impulse.kr(100), '/seconds', seconds.round(0.01));
			SendReply.kr(Impulse.kr(100), '/minutes', minutes);
		}).add;
	);
	//
	s.sync;
	//
	// GUI
	(
		w = Window("WYPYM", Rect(600, 100, 800, 500)).front.background_(Color.new255(100, 100, 100));
		~busIn = 0;
		~busOut = 1;
		w.drawFunc = {
			// fill the gradient
			Pen.addRect(w.view.bounds.insetBy(1));
			Pen.fillAxialGradient(w.view.bounds.leftTop, w.view.bounds.rightBottom, Color.new255(51, 51, 255), Color.new255(230, 0, 115));
		};

		z = w.addFlowLayout;
		//
		b = Button(w, 150 @ 50).font_(Font("Helvetica", 20));
		b.states = [["Start", Color.black, Color.green], ["Stop", Color.white, Color.red]];
		b.action = {|view|
			if (view.value == 1) {
				// start sound
				~synth = Synth(\net, [\busIn, ~busIn, \busOut, ~busOut]);
				~timer = Synth(\timer);
			} {
				~synth.release; ~synth = nil;
				~timer.free;
			};
		};
		z.nextLine;

		t = NumberBox(w, Rect(250, 20, 60, 30)).font_(Font("Helvetica", 20)).align_(\right);
		StaticText(w, Rect(260, 20, 10, 35)).string_(":").font_(Font("Helvetica", 20)).stringColor_(Color.white);
		v = NumberBox(w, Rect(275, 20, 60, 30)).font_(Font("Helvetica", 20));
		OSCFunc({arg msg;{t.value_(msg[3].value)}.defer}, '/minutes');
		OSCFunc({arg msg;{v.value_(msg[3].value)}.defer}, '/seconds');
		z.nextLine;
		//
		~centroid = EZSlider(w, 500@20, "Main freq", [10, 2e4, 'exp', 0.001].asSpec, layout: 'horz', numberWidth:70);
		~centroid.setColors(stringColor: Color.white).font_(Font("Helvetica", 14));
		OSCFunc({arg msg;{~centroid.value_(msg[3].value);}.defer}, '/centroid');
		z.nextLine;
		//
		~flatness = EZSlider(w, 500@20, "Flatness", [0, 1, 'lin', 0.001].asSpec, layout: 'horz', numberWidth:70);
		~flatness.setColors(stringColor: Color.white).font_(Font("Helvetica", 14));
		OSCFunc({arg msg;{~flatness.value_(msg[3].value);}.defer}, '/flatness');
		z.nextLine;
		//
		~entropy = EZSlider(w, 500@20, "Entropy", [0, 1, 'lin', 0.001].asSpec, layout: 'horz', numberWidth:70);
		~entropy.setColors(stringColor: Color.white).font_(Font("Helvetica", 14));
		OSCFunc({arg msg;{~entropy.value_(msg[3].value);}.defer}, '/entropy');
		z.nextLine;
		//
		~anal1 = FreqScopeView(w, Rect(0, 0, 511, 300)).freqMode_(1);
		~anal1.inBus_(~busOut).active_(true);
		ServerMeterView.new(s, w, 0@0, 1, 2);
		w.onClose_({s.freeAll; ~anal1.kill;});
	)
});

// EOF