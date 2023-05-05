//Extending functionality to the existing class with some Pseudo UGens

AdaptSpecCentroid {
	*kr {
		arg in, fftChain;
		var input, centroid, updCentroid, lowPass, highPass, rmsLow, rmsHigh, rmsDiff, integr, local;

		input = in;
		centroid = SpecCentroid.kr(fftChain); //indicator of the perceptual brightness of a signal
		local = LocalIn.kr(1, 0);
		updCentroid = ((centroid + local).lag3(1)).clip(10, 2e4);

		// The I use the centroid as a way to divide the spectrum in two parts
		lowPass = LPF.ar(LPF.ar(LPF.ar(input, updCentroid), updCentroid), updCentroid);
		highPass = HPF.ar(HPF.ar(HPF.ar(input, updCentroid), updCentroid), updCentroid);

		// Then I compute the RMS of those bands, I consider their difference and then I update the centroid in order to minimize it
		rmsLow = RMS.ar(lowPass);
		rmsHigh = RMS.ar(highPass);
		rmsDiff = rmsHigh - rmsLow; // If rmsDiff>0 it means that the high spectrum has higher magnitude. If rmsDif<0 it's the opposite
		integr = Sanitize.kr(Integrator.ar(rmsDiff)*0.01); //Sanitize.kr is to to get rid of the initial NaN
		local = integr;
		LocalOut.kr(local);

		^updCentroid;
	}
}


// EOF