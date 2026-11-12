function report = test_input_representation()
%TEST_INPUT_REPRESENTATION Public numeric APIs normalize sparse/type variants.
%   Equivalent numeric values must not depend on sparse versus dense storage
%   or exactly representable integer/single input types. Complex inputs remain
%   invalid; normalization is never permission to discard an imaginary part.
    prior_rng = rng;
    guard = onCleanup(@() rng(prior_rng)); %#ok<NASGU>
    names = {'sparse_spectral_energy_inputs', 'sparse_noiseless_readout', ...
        'sparse_seeded_noisy_readout', 'sparse_one_bin_irradiance', ...
        'exact_integer_and_single_values', 'sparse_poisson_equivalence', ...
        'complex_inputs_rejected'};

    testEnergyRepresentation();
    testNoiselessReadout();
    testNoisyReadout();
    testIrradianceRepresentation();
    testNumericTypes();
    testPoissonRepresentation();
    testComplexRejection();

    report = struct('suite', 'input_representation', 'passed', true, ...
        'test_count', numel(names), 'tests', {names});
    fprintf('PASS: Input representation, %d test groups.\n', numel(names));
end

function cfg = fixtureConfig()
    cfg = alev4.createBaselineSensor(struct('image_size', [2 3], ...
        'wavelength_nm', 550, 'bin_width_nm', 10, ...
        'qe', [0.25 0.5 0.75], 'pixel_pitch_m', 1, 'fill_factor', 1, ...
        'full_well_e', 1000, 'shot_noise', false, 'read_noise_e', 0, ...
        'gain_dn_per_e', 1, 'black_level_dn', 0));
end

function testEnergyRepresentation()
    energy = reshape(1:12, 2, 3, 2);
    wave = [450; 650];
    reference = alev4.energyToPhotons(energy, wave);
    actual = alev4.energyToPhotons(energy, sparse(wave));
    assert(isequal(actual, reference), 'Sparse wavelength normalization changed photon values.');
    assert(isa(actual, 'double') && ~issparse(actual), 'Photon output must be dense double.');
    one_bin = [0 1 2; 3 0 4];
    reference = alev4.energyToPhotons(one_bin, 550);
    actual = alev4.energyToPhotons(sparse(one_bin), sparse(550));
    assert(isequal(actual, reference), 'Sparse one-bin energy normalization changed photon values.');
    assert(~issparse(actual), 'Sparse input must not leak into photon output.');
end

function testNoiselessReadout()
    cfg = fixtureConfig();
    expected = [0 1.25 2.5; 3.75 4 0];
    reference = alev4.applyNoise(expected, cfg, 810);
    actual = alev4.applyNoise(sparse(expected), cfg, sparse(810));
    assert(isequal(actual, reference), 'Sparse noiseless readout differs from dense readout.');
    assertDenseIntermediates(actual);
    assert(isa(actual.raw_dn, 'uint16') && ~issparse(actual.raw_dn), ...
        'RAW must be a dense uint16 matrix even with zero black/read noise.');
end

function testNoisyReadout()
    cfg = fixtureConfig(); cfg.shot_noise = true; cfg.read_noise_e = 2;
    cfg.black_level_dn = 64;
    expected = [0 0.25 9.99; 10 50 2];
    reference = alev4.applyNoise(expected, cfg, 811);
    actual = alev4.applyNoise(sparse(expected), cfg, sparse(811));
    assert(isequal(actual, reference), 'Sparse storage changed seeded Poisson/read noise.');
    assertDenseIntermediates(actual);
end

function testIrradianceRepresentation()
    cfg = fixtureConfig();
    flux = [0 4 8; 12 16 20];
    reference = alev4.simulateExposure(flux, cfg, 0.25, 812);
    actual = alev4.simulateExposure(sparse(flux), cfg, sparse(0.25), sparse(812));
    assert(isequal(actual, reference), 'Sparse one-bin irradiance differs from dense simulation.');
    assertDenseIntermediates(actual);
    assert(~issparse(actual.expected_incident_photons) && ~issparse(actual.exposure_s), ...
        'Incident photons and exposure metadata must be dense.');
end

function testNumericTypes()
    cfg = fixtureConfig();
    values = [0 1 2; 3 4 5];
    for type_name = {'single', 'uint16'}
        converted = cast(values, type_name{1});
        reference = alev4.applyNoise(values, cfg, 813);
        actual = alev4.applyNoise(converted, cfg, uint32(813));
        assert(isequal(actual, reference), 'Exactly representable numeric input changed readout.');
        reference = alev4.energyToPhotons(values, 550);
        actual = alev4.energyToPhotons(converted, cast(550, type_name{1}));
        assert(isequal(actual, reference), 'Exactly representable numeric input changed photon conversion.');
        reference = alev4.simulateExposure(values, cfg, 1, 814);
        actual = alev4.simulateExposure(converted, cfg, cast(1, type_name{1}), uint32(814));
        assert(isequal(actual, reference), 'Exactly representable numeric input changed exposure integration.');
    end
end

function testPoissonRepresentation()
    means = [0 1 10; 50 2 0];
    rng(815, 'twister');
    reference = alev4.samplePoisson(means);
    alternatives = {sparse(means), single(means), uint16(means)};
    for k = 1:numel(alternatives)
        rng(815, 'twister');
        actual = alev4.samplePoisson(alternatives{k});
        assert(isequal(actual, reference), 'Input representation changed the Poisson RNG stream.');
        assert(isa(actual, 'double') && ~issparse(actual), 'Poisson samples must be dense doubles.');
    end
end

function testComplexRejection()
    cfg = fixtureConfig();
    imaginary = ones(2, 3) + 1i;
    assertError(@() alev4.energyToPhotons(imaginary, 550), 'ALEV4:InvalidEnergy');
    assertError(@() alev4.energyToPhotons(ones(2, 3), 550 + 1i), 'ALEV4:InvalidWavelength');
    assertError(@() alev4.applyNoise(imaginary, cfg, 816), 'ALEV4:InvalidExpectedElectrons');
    assertError(@() alev4.simulateExposure(imaginary, cfg, 1, 816), 'ALEV4:InvalidIrradiance');
    assertError(@() alev4.samplePoisson(imaginary), 'ALEV4:InvalidPoissonMean');
end

function assertDenseIntermediates(result)
    fields = {'expected_electrons', 'collected_electrons', 'charge_electrons', 'read_electrons'};
    for k = 1:numel(fields)
        value = result.(fields{k});
        assert(isa(value, 'double') && ~issparse(value), 'Electron intermediates must be dense double.');
    end
end

function assertError(callback, identifier)
    caught = false;
    try
        callback();
    catch err
        caught = true;
        assert(strcmp(err.identifier, identifier), ...
            sprintf('Expected %s but got %s.', identifier, err.identifier));
    end
    assert(caught, ['Expected error not raised: ' identifier]);
end
