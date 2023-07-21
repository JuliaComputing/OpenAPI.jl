# DefaultApi

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**post_urlencoded_form**](DefaultApi.md#post_urlencoded_form) | **POST** /test/{form_id}/post_urlencoded_form_data | posts a urlencoded form, with file contents and additional metadata, both of which are strings
[**upload_binary_file**](DefaultApi.md#upload_binary_file) | **POST** /test/{file_id}/upload_binary_file | uploads a binary file given its path, along with some metadata
[**upload_text_file**](DefaultApi.md#upload_text_file) | **POST** /test/{file_id}/upload_text_file | uploads text file contents along with some metadata


# **post_urlencoded_form**
> post_urlencoded_form(req::HTTP.Request, form_id::Int64; additional_metadata=nothing, file=nothing,) -> TestResponse

posts a urlencoded form, with file contents and additional metadata, both of which are strings

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **req** | **HTTP.Request** | The HTTP Request object | 
**form_id** | **Int64**| ID of form to update | [default to nothing]

### Optional Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **additional_metadata** | **String**| Additional data to pass to server | [default to nothing]
 **file** | **String**| file contents to upload, in string format | [default to nothing]

### Return type

[**TestResponse**](TestResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/x-www-form-urlencoded
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **upload_binary_file**
> upload_binary_file(req::HTTP.Request, file_id::Int64; additional_metadata=nothing, file=nothing,) -> TestResponse

uploads a binary file given its path, along with some metadata

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **req** | **HTTP.Request** | The HTTP Request object | 
**file_id** | **Int64**| ID of file to update | [default to nothing]

### Optional Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **additional_metadata** | **String**| Additional data to pass to server | [default to nothing]
 **file** | **String****String**| file to upload, must be a string representing a valid file path | [default to nothing]

### Return type

[**TestResponse**](TestResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: multipart/form-data
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **upload_text_file**
> upload_text_file(req::HTTP.Request, file_id::Int64; additional_metadata=nothing, file=nothing,) -> TestResponse

uploads text file contents along with some metadata

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **req** | **HTTP.Request** | The HTTP Request object | 
**file_id** | **Int64**| ID of file to update | [default to nothing]

### Optional Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **additional_metadata** | **String**| Additional data to pass to server, a string | [default to nothing]
 **file** | **String**| file contents to upload in base64 encoded format | [default to nothing]

### Return type

[**TestResponse**](TestResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: multipart/form-data
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

