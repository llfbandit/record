#pragma once

#include <memory>
#include <flutter/encodable_value.h>
#include <tchar.h>
#include <comdef.h>
#include <system_error>

template <typename T>
static bool GetValueFromEncodableMap(const flutter::EncodableMap* map,
	const char* key, T& out) {
	auto iter = map->find(flutter::EncodableValue(key));
	if (iter != map->end() && !iter->second.IsNull()) {
		if (auto* value = std::get_if<T>(&iter->second)) {
			out = *value;
			return true;
		}
	}
	return false;
}

//////////////////////////////////////////////////////////////////////////
//  COM Safe release
//////////////////////////////////////////////////////////////////////////

template <class T> void SafeRelease(T** ppT)
{
	if (*ppT)
	{
		(*ppT)->Release();
		*ppT = NULL;
	}
}

template <class T> inline void SafeRelease(T*& pT)
{
	if (pT != NULL)
	{
		pT->Release();
		pT = NULL;
	}
}

inline std::string Utf8FromUtf16(const wchar_t* utf16_string) {
	if (!utf16_string) return {};

	int len = static_cast<int>(wcslen(utf16_string));
	if (len == 0) return {};

	int target_length = ::WideCharToMultiByte(
		CP_UTF8, WC_ERR_INVALID_CHARS,
		utf16_string, len,
		nullptr, 0,
		nullptr, nullptr
	);
	if (target_length == 0) return {};

	std::string result(target_length, '\0');

	::WideCharToMultiByte(
		CP_UTF8, WC_ERR_INVALID_CHARS,
		utf16_string, len,
		result.data(), target_length,
		nullptr, nullptr
	);

	return result;
}


inline std::wstring Utf16FromUtf8(const std::string& utf8_string) {
	if (utf8_string.empty()) return {};

	int len = static_cast<int>(utf8_string.length());
	int target_length = ::MultiByteToWideChar(
		CP_UTF8, MB_ERR_INVALID_CHARS,
		utf8_string.data(), len,
		nullptr, 0
	);
	if (target_length == 0) return {};

	std::wstring result(target_length, L'\0');

	::MultiByteToWideChar(
		CP_UTF8, MB_ERR_INVALID_CHARS,
		utf8_string.data(), len,
		result.data(), target_length
	);

	return result;
}
