function photon_irradiance = energyToPhotons(energy_irradiance, wavelength_nm)
%ENERGYTOPHOTONS Convert W/(m^2 nm) into photons/(m^2 s nm).
%   Spectral energy density is multiplied by wavelength/(h*c). The nm to m
%   conversion applies ONLY to photon energy, not to the integration bins.
%   Accepted real numerical inputs are normalized to dense doubles before
%   spectral reshaping, including sparse wavelength vectors/one-bin images.
    if ~isnumeric(energy_irradiance) || ~isreal(energy_irradiance) || ...
            ndims(energy_irradiance) > 3 || isempty(energy_irradiance) || ...
            any(~isfinite(energy_irradiance(:))) || any(energy_irradiance(:) < 0)
        error('ALEV4:InvalidEnergy', 'Energy irradiance must be finite, real and nonnegative.');
    end
    if ~isnumeric(wavelength_nm) || ~isreal(wavelength_nm) || ~isvector(wavelength_nm) || ...
            isempty(wavelength_nm) || any(~isfinite(wavelength_nm(:))) || ...
            any(wavelength_nm(:) <= 0) || any(diff(wavelength_nm(:)) <= 0) || ...
            size(energy_irradiance, 3) ~= numel(wavelength_nm)
        error('ALEV4:InvalidWavelength', 'Positive increasing wavelengths must match the spectral dimension.');
    end
    h = 6.62607015e-34; % SI exact, J s
    c = 299792458;     % SI exact, m/s
    wavelength_nm = full(double(wavelength_nm(:)));
    energy_irradiance = double(energy_irradiance);
    if issparse(energy_irradiance), energy_irradiance = full(energy_irradiance); end
    factor = wavelength_nm * 1e-9 / (h * c);
    photon_irradiance = bsxfun(@times, energy_irradiance, reshape(factor, 1, 1, []));
    if any(~isfinite(photon_irradiance(:)))
        error('ALEV4:SignalOverflow', 'Photon irradiance conversion overflowed.');
    end
end
